# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::AvatarUpload do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  def upload(width: 96, height: 96, format: ".png")
    image = Vips::Image.black(width, height).new_from_image([ 120, 40, 90 ])
    file = Tempfile.new([ "avatar", format ], binmode: true)
    image.write_to_file(file.path)
    file.rewind
    file
  end

  # A red left side and a blue right side, so a crop can be told apart from the
  # centred square.
  def two_colour_upload(width: 1200, height: 600, blue: 300)
    left = Vips::Image.black(width - blue, height).new_from_image([ 255, 0, 0 ])
    right = Vips::Image.black(blue, height).new_from_image([ 0, 0, 255 ])
    file = Tempfile.new([ "avatar", ".png" ], binmode: true)
    left.join(right, :horizontal).write_to_file(file.path)
    file.rewind
    file
  end

  def raw_upload(bytes, suffix: ".png")
    file = Tempfile.new([ "avatar", suffix ], binmode: true)
    file.write(bytes)
    file.rewind
    file
  end

  def stored(user)
    Vips::Image.new_from_buffer(user.avatar.download, "")
  end

  it "attaches a normalized square WebP" do
    described_class.new(user:).call(upload(width: 800, height: 200, format: ".jpg"))

    expect(user.avatar).to be_attached
    expect(user.avatar.content_type).to eq("image/webp")
    expect([ stored(user).width, stored(user).height ]).to eq([ 512, 512 ])
  end

  it "keeps the square the account chose" do
    described_class.new(user:).call(
      two_colour_upload,
      crop: { x: 900, y: 0, size: 300, width: 1200, height: 600 }
    )

    red, _green, blue = stored(user).getpoint(256, 256)
    expect(blue).to be > 200
    expect(red).to be < 60
  end

  it "scales a square measured on a larger image" do
    described_class.new(user:).call(
      two_colour_upload,
      crop: { x: 1800, y: 0, size: 600, width: 2400, height: 1200 }
    )

    red, _green, blue = stored(user).getpoint(256, 256)
    expect(blue).to be > 200
    expect(red).to be < 60
  end

  it "falls back to the centred square when the square does not fit the image" do
    described_class.new(user:).call(
      two_colour_upload,
      crop: { x: 900, y: 0, size: 300, width: 600, height: 1200 }
    )

    red, _green, blue = stored(user).getpoint(256, 256)
    expect(red).to be > 200
    expect(blue).to be < 60
  end

  it "rejects an upload above the byte limit" do
    bytes = "\x89PNG\r\n\x1a\n".b + ("x" * (described_class::MAX_BYTES + 1))

    expect { described_class.new(user:).call(raw_upload(bytes)) }
      .to raise_error(described_class::Invalid, I18n.t("settings.profile.avatar_errors.too_large", max: 20))
  end

  it "rejects a type outside the allowlist" do
    expect { described_class.new(user:).call(raw_upload("GIF89a-not-accepted")) }
      .to raise_error(described_class::Invalid, I18n.t("settings.profile.avatar_errors.unsupported_type"))
  end

  it "rejects a malformed image carrying a valid signature" do
    expect { described_class.new(user:).call(raw_upload("\x89PNG\r\n\x1a\n".b + "garbage")) }
      .to raise_error(described_class::Invalid, I18n.t("settings.profile.avatar_errors.unreadable"))
  end

  it "rejects an image larger than the maximum dimension" do
    expect { described_class.new(user:).call(upload(width: 9000, height: 32)) }
      .to raise_error(described_class::Invalid,
        I18n.t("settings.profile.avatar_errors.too_large_dimensions", max: described_class::MAX_DIMENSION))
  end

  it "accepts a phone photo wider than the former limit and decodes it reduced" do
    described_class.new(user:).call(upload(width: 5000, height: 3000, format: ".jpg"))

    expect(user.avatar).to be_attached
    expect([ stored(user).width, stored(user).height ]).to eq([ 512, 512 ])
  end

  it "keeps the previous avatar when a replacement is rejected" do
    described_class.new(user:).call(upload)
    previous = user.avatar.blob

    expect { described_class.new(user:).call(raw_upload("nope")) }
      .to raise_error(described_class::Invalid)

    expect(user.reload.avatar.blob).to eq(previous)
  end

  it "purges the replaced blob" do
    described_class.new(user:).call(upload)
    previous = user.avatar.blob

    perform_enqueued_jobs { described_class.new(user:).call(upload) }

    expect(ActiveStorage::Blob.find_by(id: previous.id)).to be_nil
  end
end
