# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PhotoOrder do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let(:start) { Time.utc(2026, 5, 1, 8) }

  def photo(position:, taken_at_local: nil, track_elapsed: nil)
    attributes = { workout:, user:, position:, taken_at_local: }
    if track_elapsed
      attributes.merge!(location: Workouts::PhotoPlacement::FACTORY.point(6.0, 45.0),
                        location_source: "time", track_distance: 100.0, track_elapsed:)
    end
    create(:workout_photo, **attributes)
  end

  it "orders by capture time, then by route position, then upload order" do
    late = photo(position: 0, taken_at_local: start + 2.hours)
    early = photo(position: 1, taken_at_local: start + 1.hour)
    placed = photo(position: 2, track_elapsed: 600)
    untimed = photo(position: 3)

    described_class.new(workout:).apply

    expect(workout.photos.reload.map(&:id)).to eq([ early.id, late.id, placed.id, untimed.id ])
  end

  it "applies the camera-clock correction to the capture times" do
    workout.update!(photo_time_offset_seconds: 3600)
    first = photo(position: 0, taken_at_local: start + 2.hours)
    second = photo(position: 1, taken_at_local: start + 1.hour)

    described_class.new(workout:).apply

    expect(workout.photos.reload.map(&:id)).to eq([ second.id, first.id ])
  end

  it "leaves a manual order alone" do
    workout.update!(photos_ordered_by_owner: true)
    late = photo(position: 0, taken_at_local: start + 2.hours)
    early = photo(position: 1, taken_at_local: start + 1.hour)

    described_class.new(workout:).apply

    expect(workout.photos.reload.map(&:id)).to eq([ late.id, early.id ])
  end

  it "resumes the automatic order on demand" do
    workout.update!(photos_ordered_by_owner: true)
    late = photo(position: 0, taken_at_local: start + 2.hours)
    early = photo(position: 1, taken_at_local: start + 1.hour)

    described_class.new(workout:).resume_automatic!

    expect(workout.reload).not_to be_photos_ordered_by_owner
    expect(workout.photos.reload.map(&:id)).to eq([ early.id, late.id ])
  end
end
