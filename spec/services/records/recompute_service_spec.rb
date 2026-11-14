# frozen_string_literal: true

require "rails_helper"

RSpec.describe Records::RecomputeService do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def create_workout(started_at:, distance:, ascent:, moving:, average_speed:, max_speed:, average_pace:, best_pace:)
    create(:workout, user:, sport:, started_at:,
      distance:, ascent:,
      duration: moving + 100, moving_time: moving, pause_time: 100,
      average_speed:, max_speed:, average_pace:, best_pace:)
  end

  def record_for(type)
    Record.find_by!(user:, sport:, record_type: type)
  end

  describe "winners" do
    let!(:w1) do
      create_workout(started_at: Time.zone.parse("2026-01-01 06:00"), distance: 1000, ascent: 50,
        moving: 600, average_speed: 5.0, max_speed: 8.0, average_pace: 200, best_pace: 180)
    end
    let!(:w2) do
      create_workout(started_at: Time.zone.parse("2026-02-01 06:00"), distance: 2000, ascent: 30,
        moving: 900, average_speed: 6.0, max_speed: 9.0, average_pace: 180, best_pace: 170)
    end
    let!(:w3) do
      create_workout(started_at: Time.zone.parse("2026-03-01 06:00"), distance: 500, ascent: 10,
        moving: 300, average_speed: 4.0, max_speed: nil, average_pace: nil, best_pace: 170)
    end

    before { described_class.new(user:, sport:).call }

    it "picks the winning workout and value per type" do
      expect(record_for("FD")).to have_attributes(workout: w2, value: 2000)
      expect(record_for("HA")).to have_attributes(workout: w1, value: 50)
      expect(record_for("LD")).to have_attributes(workout: w2, value: 900)
      expect(record_for("AS")).to have_attributes(workout: w2, value: 6.0)
      expect(record_for("MS")).to have_attributes(workout: w2, value: 9.0)
      expect(record_for("AP")).to have_attributes(workout: w2, value: 180)
      expect(record_for("BP")).to have_attributes(workout: w2, value: 170)
    end

    it "denormalizes the winning workout date for display" do
      expect(record_for("FD").workout_started_at).to eq(w2.started_at)
    end

    it "breaks ties on the earlier start" do
      # W2 and W3 tie on best pace at 170; W2 started first, so it holds BP.
      expect(record_for("BP").workout).to eq(w2)
    end

    it "passes over a figure an anomaly contests, keeping the workout's other records" do
      w2.update!(contested_metrics: %w[best_pace max_speed])

      expect(record_for("MS")).to have_attributes(workout: w1, value: 8.0)
      expect(record_for("BP")).to have_attributes(workout: w3, value: 170)
      expect(record_for("FD")).to have_attributes(workout: w2, value: 2000)
    end

    it "passes over a contested ascent" do
      w1.update!(ascent: 900, contested_metrics: %w[ascent])

      described_class.new(user:, sport:).call

      expect(record_for("HA")).to have_attributes(workout: w2, value: 30)
    end

    it "is a no-op on re-run" do
      ids_before = Record.where(user:, sport:).pluck(:id, :record_type, :workout_id, :value)

      described_class.new(user:, sport:).call

      expect(Record.where(user:, sport:).pluck(:id, :record_type, :workout_id, :value)).to eq(ids_before)
    end
  end

  describe "ties, zeroes, and nulls" do
    it "breaks a full tie on the earlier row" do
      w1 = create_workout(started_at: Time.zone.parse("2026-01-01 06:00"), distance: 1000, ascent: 10,
        moving: 100, average_speed: 5.0, max_speed: 8.0, average_pace: 200, best_pace: 180)
      create_workout(started_at: Time.zone.parse("2026-01-01 06:00"), distance: 1000, ascent: 10,
        moving: 100, average_speed: 5.0, max_speed: 8.0, average_pace: 200, best_pace: 180)

      described_class.new(user:, sport:).call

      expect(record_for("FD").workout).to eq(w1)
    end

    it "keeps a genuine zero instead of treating it as missing" do
      w = create_workout(started_at: Time.zone.parse("2026-01-01 06:00"), distance: 0, ascent: 0,
        moving: 0, average_speed: 0, max_speed: 0, average_pace: nil, best_pace: nil)

      described_class.new(user:, sport:).call

      expect(record_for("FD")).to have_attributes(workout: w, value: 0)
      expect(record_for("HA")).to have_attributes(workout: w, value: 0)
    end

    it "keeps no row for a type with only NULL candidates" do
      create_workout(started_at: Time.zone.parse("2026-01-01 06:00"), distance: 1000, ascent: 10,
        moving: 100, average_speed: 5.0, max_speed: nil, average_pace: nil, best_pace: nil)

      described_class.new(user:, sport:).call

      expect(Record.where(user:, sport:, record_type: %w[AP BP MS]).count).to eq(0)
      expect(Record.where(user:, sport:).count).to eq(4)
    end

    it "removes a row whose winner disappears" do
      w = create_workout(started_at: Time.zone.parse("2026-01-01 06:00"), distance: 1000, ascent: 10,
        moving: 100, average_speed: 5.0, max_speed: 8.0, average_pace: 200, best_pace: 180)
      described_class.new(user:, sport:).call
      expect(record_for("AP").workout).to eq(w)

      w.update_column(:average_pace, nil)
      described_class.new(user:, sport:).call

      expect(Record.where(user:, sport:, record_type: "AP").count).to eq(0)
    end
  end

  describe "biggest climb (MC)" do
    let(:running) { catalog_sport("running") }

    def max_climb_record
      Record.find_by(user:, sport: running, record_type: "MC")
    end

    it "picks the workout with the largest detected climb" do
      small = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-01-01 06:00"))
      big = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-02-01 06:00"))
      create(:detected_lap, :climb, workout: small, ascent: 90.0)
      create(:detected_lap, :climb, workout: big, ascent: 210.0)

      described_class.new(user:, sport: running).call

      expect(max_climb_record).to have_attributes(workout: big, value: 210.0)
    end

    it "removes MC when no climb remains" do
      workout = create(:workout, user:, sport: running)
      create(:detected_lap, :climb, workout:)
      described_class.new(user:, sport: running).call
      expect(max_climb_record).to be_present

      workout.detected_laps.delete_all
      described_class.new(user:, sport: running).call

      expect(max_climb_record).to be_nil
    end

    it "keeps no MC row for a sport without recorded elevation" do
      flat = create(:sport, records_elevation: false)
      create(:detected_lap, :climb, workout: create(:workout, user:, sport: flat), ascent: 300.0)

      described_class.new(user:, sport: flat).call

      expect(Record.where(user:, sport: flat, record_type: "MC").count).to eq(0)
    end
  end

  describe "effort records" do
    let(:running) { catalog_sport("running") }

    def effort_record_for(key)
      EffortRecord.find_by(user:, sport: running, distance_key: key)
    end

    it "picks the fastest effort per distance" do
      slower = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-01-01 06:00"))
      faster = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-02-01 06:00"))
      create(:best_effort, workout: slower, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_500)
      create(:best_effort, workout: faster, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_400)
      create(:best_effort, workout: slower, distance_key: "km10", distance_meters: 10_000, duration_seconds: 3_100)

      described_class.new(user:, sport: running).call

      expect(effort_record_for("km5")).to have_attributes(workout: faster, duration_seconds: 1_400)
      expect(effort_record_for("km10")).to have_attributes(workout: slower, duration_seconds: 3_100)
    end

    it "breaks ties on the earlier effort start" do
      earlier = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-01-01 06:00"))
      later = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-02-01 06:00"))
      create(:best_effort, workout: later, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_400)
      create(:best_effort, workout: earlier, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_400)

      described_class.new(user:, sport: running).call

      expect(effort_record_for("km5").workout).to eq(earlier)
    end

    it "steals the record from the previous holder" do
      first = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-01-01 06:00"))
      create(:best_effort, workout: first, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_500)
      described_class.new(user:, sport: running).call
      expect(effort_record_for("km5").workout).to eq(first)

      second = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-02-01 06:00"))
      create(:best_effort, workout: second, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_400)
      described_class.new(user:, sport: running).call

      expect(effort_record_for("km5").workout).to eq(second)
      expect(first.effort_records).to be_empty
    end

    it "removes an effort record when its only effort disappears" do
      workout = create(:workout, user:, sport: running)
      effort = create(:best_effort, workout:, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_400)
      described_class.new(user:, sport: running).call
      expect(effort_record_for("km5")).to be_present

      effort.destroy!
      described_class.new(user:, sport: running).call

      expect(effort_record_for("km5")).to be_nil
    end

    it "re-points to the runner-up when the winning workout is deleted" do
      winner = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-01-01 06:00"))
      runner_up = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-02-01 06:00"))
      create(:best_effort, workout: winner, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_400)
      create(:best_effort, workout: runner_up, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_500)
      described_class.new(user:, sport: running).call

      winner.destroy!

      expect(effort_record_for("km5").workout).to eq(runner_up)
    end

    it "keeps no effort rows for a sport without an effort profile" do
      other = create(:sport)
      workout = create(:workout, user:, sport: other)
      create(:best_effort, workout:, distance_key: "km5", distance_meters: 5_000, duration_seconds: 1_400)

      described_class.new(user:, sport: other).call

      expect(EffortRecord.where(user:, sport: other).count).to eq(0)
    end

    it "upserts the rowing standard distances from its best efforts" do
      rowing = catalog_sport("rowing")
      workout = create(:workout, user:, sport: rowing)
      create(:best_effort, workout:, distance_key: "km2", distance_meters: 2_000, duration_seconds: 400)

      described_class.new(user:, sport: rowing).call

      expect(EffortRecord.find_by(user:, sport: rowing, distance_key: "km2")).to be_present
      expect(EffortRecord.where(user:, sport: rowing, distance_key: "marathon")).to be_empty
    end
  end
end
