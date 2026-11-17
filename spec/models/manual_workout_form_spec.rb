# frozen_string_literal: true

require "rails_helper"

# The web form of a manual entry (docs/dev/MANUAL-ENTRY.md): typed in the
# account's units and time zone, read into SI.
RSpec.describe ManualWorkoutForm do
  let(:user) { create(:user, time_zone: "Europe/Paris", unit_system: "metric") }
  let(:running) { catalog_sport("running") }
  let(:params) do
    { sport_id: running.id.to_s, started_at: "2026-10-17T07:30", duration_hours: "1", duration_minutes: "5",
      duration_seconds: "", distance: "12,5", ascent: "140", average_heart_rate: "151", title: " Footing " }
  end

  def form_for(values, account: user) = described_class.from_params(values, user: account)

  it "reads the figures into SI in the account's time zone" do
    attributes = form_for(params).to_attributes

    expect(attributes).to include(sport: running, duration: 3900, moving_time: nil, distance: 12_500.0, ascent: 140.0,
                                  average_heart_rate: 151, max_heart_rate: nil, title: "Footing", commute: false)
    expect(attributes[:started_at]).to eq(Time.utc(2026, 10, 17, 5, 30))
  end

  it "reads miles and feet for an imperial account" do
    imperial = create(:user, time_zone: "America/New_York", unit_system: "imperial")

    attributes = form_for(params.merge(distance: "10", ascent: "1000"), account: imperial).to_attributes

    expect(attributes[:distance]).to be_within(0.01).of(16_093.44)
    expect(attributes[:ascent]).to be_within(0.01).of(304.8)
    expect(attributes[:started_at]).to eq(Time.utc(2026, 10, 17, 11, 30))
  end

  it "names every field it cannot read" do
    form = form_for(params.merge(sport_id: "", started_at: "demain", duration_hours: "", duration_minutes: "",
                                 distance: "douze", calories: "1,5"))

    expect(form.to_attributes).to be_nil
    expect(form.errors.attribute_names).to contain_exactly(:sport_id, :started_at, :duration, :distance, :calories)
  end

  it "fills itself back from a manual entry, keeping an implicit moving time empty" do
    entry = create(:workout, :manual, user:, sport: running, started_at: Time.utc(2026, 10, 17, 5, 30),
                                      duration: 3900, moving_time: 3900, distance: 12_500, ascent: 0)

    form = described_class.from_workout(entry, user:)

    expect(form).to have_attributes(started_at: "2026-10-17T07:30", duration_hours: "1", duration_minutes: "5",
                                    duration_seconds: "0", moving_hours: nil, distance: "12,5", ascent: nil)
  end

  it "shows the model's refusals under their fields" do
    form = form_for(params)
    workout = Workout.new(origin: "manual")
    workout.errors.add(:pause_time, :invalid)
    workout.errors.add(:max_heart_rate, :below_average)

    form.adopt_errors(workout)

    expect(form.errors.attribute_names).to contain_exactly(:moving_time, :max_heart_rate)
  end
end
