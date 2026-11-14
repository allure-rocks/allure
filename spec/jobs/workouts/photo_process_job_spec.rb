# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PhotoProcessJob do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let(:body) { photo_bytes(width: 2400, height: 1200) }
  let(:photo) { Workouts::PhotoUpload.new(user:, workout:).call(StringIO.new(body)) }

  it "keeps the original and strips metadata from both bounded WebP derivatives" do
    described_class.perform_now(photo)
    expect(photo.reload).to be_ready
    expect(photo.original.download).to eq(body)
    [ [ photo.display, 2048 ], [ photo.thumbnail, 480 ] ].each do |attachment, limit|
      image = Vips::Image.new_from_buffer(attachment.download, "")
      expect(image.width).to be <= limit
      expect(image.get_fields.grep(/exif|xmp|icc/)).to be_empty
      expect(attachment.content_type).to eq("image/webp")
    end
    expect(photo.bytes_total).to eq(photo.original.byte_size + photo.display.byte_size + photo.thumbnail.byte_size)
    expect { described_class.perform_now(photo) }.not_to change(ActiveStorage::Blob, :count)
  end

  it "fails unreadable data without losing the original" do
    broken = Workouts::PhotoUpload.new(user:, workout:).call(StringIO.new("\xFF\xD8\xFFbroken".b))
    described_class.perform_now(broken)
    expect(broken.reload).to be_failed
    expect(broken.failure_reason).to eq("unreadable")
    expect(broken.original).to be_attached
    expect(broken.display).not_to be_attached
  end

  it "applies EXIF orientation before resizing" do
    rotated = Workouts::PhotoUpload.new(user:, workout:).call(StringIO.new(photo_bytes(width: 90, height: 60, orientation: 6)))
    described_class.perform_now(rotated)
    expect(rotated.reload).to have_attributes(width: 60, height: 90, status: "ready")
  end

  it "cleans orphaned derivative blobs if attaching the second output fails" do
    photo
    allow(photo.thumbnail).to receive(:attach).and_raise(IOError, "storage failed")
    expect { described_class.perform_now(photo) }.not_to change(ActiveStorage::Blob, :count)
    expect(photo.reload).to be_failed
    expect(photo.original).to be_attached
    expect(photo.display).not_to be_attached
  end

  it "enforces the pixel guard before normalization" do
    image = double(width: 12_001, height: 10)
    allow(Vips::Image).to receive(:new_from_file).and_return(image)
    described_class.perform_now(photo)
    expect(photo.reload.failure_reason).to eq("too_large_dimensions")
  end

  it "does not silently exceed the quota with derivatives" do
    photo
    user.update!(photo_quota_bytes: body.bytesize)
    described_class.perform_now(photo)
    expect(photo.reload.failure_reason).to eq("quota_exceeded")
    expect(photo.bytes_total).to eq(body.bytesize)
    expect(photo.display).not_to be_attached
  end

  it "recovers processing rows older than ten minutes" do
    photo.update!(updated_at: 11.minutes.ago)
    expect { Workouts::PhotoRecoveryJob.perform_now }.to have_enqueued_job(described_class).with(photo)
  end

  it "orders the gallery by capture time as photos finish processing" do
    late = Workouts::PhotoUpload.new(user:, workout:).call(
      StringIO.new(photo_bytes(exif: photo_exif(taken_at: "2026:05:01 12:00:30")))
    )
    early = Workouts::PhotoUpload.new(user:, workout:).call(
      StringIO.new(photo_bytes(exif: photo_exif(taken_at: "2026:05:01 10:00:30")))
    )

    described_class.perform_now(late)
    described_class.perform_now(early)

    expect(workout.photos.reload.map(&:id)).to eq([ early.id, late.id ])
  end
end
