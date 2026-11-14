# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PhotoPlacement do
  let(:user) { create(:user, time_zone: "UTC") }
  let(:workout) { create(:workout, user:) }
  let(:photo) { Workouts::PhotoUpload.new(user:, workout:).call(StringIO.new(photo_bytes(exif:))) }
  let(:exif) { photo_exif(taken_at: "2026:08:23 06:00:30", offset: "+00:00") }

  before { create(:track_segment, workout:) }

  def process! = Workouts::PhotoProcessJob.perform_now(photo).then { photo.reload }

  it "reads the EXIF facts while processing and places the photo by its capture time" do
    process!

    expect(photo.taken_at_local).to eq(Time.utc(2026, 8, 23, 6, 0, 30))
    expect(photo.taken_at_utc_offset).to eq(0)
    expect(photo.location_source).to eq("time")
    expect(photo.track_distance).to be_within(0.1).of(125.0)
    expect(photo.track_elapsed).to be_within(0.1).of(30.0)
  end

  context "with a GPS position near the route" do
    let(:exif) { photo_exif(taken_at: "2026:08:23 06:00:05", offset: "+00:00", lon: 6.4083, lat: 45.0719) }

    it "prefers the position over the time" do
      process!

      expect(photo.location_source).to eq("exif")
      expect(photo.location.y).to be_within(1e-5).of(45.0719)
      expect(photo.track_distance).to be_within(2).of(125.0)
    end
  end

  context "without an offset in the file" do
    let(:user) { create(:user, time_zone: "Europe/Paris") }
    let(:exif) { photo_exif(taken_at: "2026:08:23 08:00:30") }

    it "reads the wall clock in the account's time zone" do
      process!

      expect(photo.location_source).to eq("time")
      expect(photo.track_elapsed).to be_within(0.1).of(30.0)
    end
  end

  it "applies the camera-clock correction and leaves the owner's choices alone" do
    workout.update!(photo_time_offset_seconds: 3_600)
    process!
    expect(photo.location_source).to eq("none")

    workout.update!(photo_time_offset_seconds: 0)
    described_class.new(workout: workout.reload).refresh_all
    expect(photo.reload.location_source).to eq("time")

    described_class.new(workout:).clear(photo)
    described_class.new(workout:).refresh_all
    expect(photo.reload.location_source).to eq("cleared")
    expect(photo.location).to be_nil
  end

  it "snaps a manual placement onto the line, refuses a far one, and can hand back to the automatic placement" do
    process!
    service = described_class.new(workout:)

    expect(service.place(photo, longitude: 6.40835, latitude: 45.07185)).to be(true)
    expect(photo.reload.location_source).to eq("manual")
    expect(service.place(photo, longitude: 7.0, latitude: 45.0)).to be(false)
    expect(photo.reload.location_source).to eq("manual")

    service.automatic(photo)
    expect(photo.reload.location_source).to eq("time")
  end

  it "re-places photos after a re-analysis" do
    process!
    expect { Workouts::PhotoPlacementJob.perform_now(workout) }.not_to(change { photo.reload.track_distance })
  end
end
