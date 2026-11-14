# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiles::SharedStatistics do
  let(:user) { create(:user, profile_statistics_audience: "members") }
  let(:viewer) { create(:user) }
  let(:sport) { catalog_sport("cycling") }

  it "does not query the workout history without the opt-in" do
    user.profile_statistics_audience = "none"
    expect(user).not_to receive(:workouts)

    expect(described_class.new(user:, viewer:).call).to be_empty
  end

  it "shares only four all-history totals, including unpublished, manual and credited workouts" do
    create(:workout, user:, sport:, started_at: 5.years.ago, distance: 1_000, duration: 310, moving_time: 300, ascent: 50,
                     average_heart_rate: 150, average_power: 250)
    create(:workout, :manual, user:, sport:, distance: 2_000, duration: 600, moving_time: 600)
    source = create(:workout, sport:, distance: 3_000, duration: 910, moving_time: 900, ascent: 100)
    create(:workout, :credit, user:, sport:, credited_from: source, distance: 3_000, duration: 910, moving_time: 900, ascent: 100)
    create(:workout, user: create(:user), sport:, distance: 99_000)

    row = described_class.new(user:, viewer:).call.sole

    expect(row.to_h).to eq(sport:, total_workouts: 3, total_distance: 6_000, total_duration: 1_800, total_ascent: 150)
  end

  it "does not truncate the whole history at the personal statistics page's recent limit" do
    attributes = build(:workout, :manual, user:, sport:).attributes.except("id", "uuid", "created_at", "updated_at")
    Workout.insert_all!(Array.new(2_001) { attributes.dup })

    row = described_class.new(user:, viewer:).call.sole

    expect(row.total_workouts).to eq(2_001)
    expect(row.total_distance).to eq(20_010_000)
  end

  it "keeps unknown measurements absent rather than inventing zeros" do
    create(:workout, :manual, user:, sport: catalog_sport("fitness"), distance: 0, average_speed: 0, average_pace: nil)

    row = described_class.new(user:, viewer:).call.sole

    expect(row.total_workouts).to eq(1)
    expect(row.total_distance).to be_nil
    expect(row.total_ascent).to be_nil
    expect(row.total_duration).to eq(3_600)
  end

  it "omits elevation for sports that do not use it and keeps sport catalog order" do
    cycling = create(:workout, user:, sport:)
    rowing = create(:workout, user:, sport: catalog_sport("rowing"), ascent: 123)

    rows = described_class.new(user:, viewer:).call

    expect(rows.map(&:sport)).to eq([ cycling.sport, rowing.sport ].sort_by(&:position))
    expect(rows.find { |row| row.sport == rowing.sport }.total_ascent).to be_nil
  end

  it "does not share a deactivated account's history" do
    user.suspended_at = Time.current
    expect(user).not_to receive(:workouts)

    expect(described_class.new(user:, viewer:).call).to be_empty
  end

  it "does not query the workout history outside the selected audience" do
    user.profile_statistics_audience = "followers"
    expect(user).not_to receive(:workouts)

    expect(described_class.new(user:, viewer:).call).to be_empty
  end

  it "never queries totals for an anonymous reader, even with the members audience" do
    expect(user).not_to receive(:workouts)

    expect(described_class.new(user:, viewer: nil).call).to be_empty
  end
end
