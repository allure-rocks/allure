# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PhotoUpload do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  subject(:service) { described_class.new(user:, workout:) }

  it "stores the unchanged original, reserves its bytes and enqueues processing" do
    body = photo_bytes
    expect { service.call(StringIO.new(body)) }.to have_enqueued_job(Workouts::PhotoProcessJob)
    photo = workout.photos.sole
    expect(photo.original.download).to eq(body)
    expect(photo.original_content_type).to eq("image/jpeg")
    expect(photo.bytes_total).to eq(body.bytesize)
    expect(photo).to be_processing
  end

  it "does not trust the name or claimed content type" do
    expect { service.call(StringIO.new("not a photo")) }.to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:unsupported_type) }
    expect(workout.photos).to be_empty
  end

  it "bounds the read before storage" do
    expect { service.call(StringIO.new("x" * (Allure::Photos::Config::MAX_BYTES + 1))) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:too_large) }
  end

  it "enforces the account quota including processing uploads on other workouts" do
    body = photo_bytes
    user.update!(photo_quota_bytes: body.bytesize)
    service.call(StringIO.new(body))
    another = create(:workout, user:)
    expect { described_class.new(user:, workout: another).call(StringIO.new(body)) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:quota_exceeded) }
  end

  it "allows a zero quota and refuses new uploads" do
    user.update!(photo_quota_bytes: 0)
    expect { service.call(StringIO.new(photo_bytes)) }.to raise_error(described_class::Invalid)
  end

  it "limits count server-side" do
    create_list(:workout_photo, 20, workout:)
    expect { service.call(StringIO.new(photo_bytes)) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:too_many) }
  end

  it "gates HEIC on the runtime decoder" do
    allow(Allure::Photos::Config).to receive(:heic_supported?).and_return(false)
    expect { service.call(StringIO.new("\x00\x00\x00\x18ftypheicmore".b)) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq(:heic_unavailable) }
  end

  it "refuses credit rows and a different owner" do
    expect { described_class.new(user: create(:user), workout:).call(StringIO.new(photo_bytes)) }.to raise_error(ActiveRecord::RecordNotFound)
    credit = create(:workout, :credit, user:)
    expect { described_class.new(user:, workout: credit).call(StringIO.new(photo_bytes)) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "uses the instance default when there is no override" do
    with_photo_env("PHOTOS_QUOTA_MB" => "3") { expect(Workouts::PhotoQuota.new(user:).limit).to eq(3.megabytes) }
  end
end
