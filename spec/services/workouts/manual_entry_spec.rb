# frozen_string_literal: true

require "rails_helper"

# A workout typed in by hand (PLAN_MANUAL_ENTRY.md): no file, no geometry,
# only the declared figures and what follows from them.
RSpec.describe Workouts::ManualEntry do
  let(:user) { create(:user) }
  let(:running) { catalog_sport("running") }
  let(:attributes) do
    { sport: running, started_at: 2.hours.ago, duration: 3000, moving_time: 2700, distance: 9_000.0, ascent: 80.0,
      average_heart_rate: 145, max_heart_rate: 172, calories: 600, title: "Footing" }
  end

  def create_entry(equipment_ids: nil, **overrides)
    Workouts::ManualEntry.create(user:, attributes: attributes.merge(overrides), equipment_ids:)
  end

  describe ".create" do
    it "stores a manual entry with its figures and what follows from them" do
      result = create_entry

      expect(result).to be_success
      expect(result.workout.reload).to have_attributes(
        origin: "manual", duration: 3000, moving_time: 2700, pause_time: 300, distance: 9_000,
        ascent: 80, descent: 0, average_heart_rate: 145, max_heart_rate: 172, calories: 600,
        start_point: nil, bounds: nil, points_count: nil, import_format: nil, max_speed: nil, best_pace: nil
      )
      expect(result.workout.average_speed.to_f).to be_within(0.0001).of(9_000.0 / 2700)
      expect(result.workout.average_pace).to eq(300)
      expect(result.workout).to be_manual
      expect(result.workout).not_to be_positioned
      expect(result.workout.original_file).not_to be_attached
    end

    it "takes the whole duration as moving time and stores no distance when none is given" do
      result = create_entry(moving_time: nil, distance: nil, ascent: nil)

      expect(result.workout.reload).to have_attributes(moving_time: 3000, pause_time: 0, distance: 0, ascent: 0,
                                                       average_pace: nil)
      expect(result.workout.average_speed).to eq(0)
    end

    it "enqueues no derivation of a recording" do
      expect { create_entry }.not_to have_enqueued_job
      expect(TrackSegment.count).to eq(0)
    end

    it "attaches the equipment and counts the entry in its totals" do
      shoes = create(:equipment, user:)

      create_entry(equipment_ids: [ shoes.id ])

      expect(shoes.reload).to have_attributes(total_workouts: 1, total_distance: 9_000, total_moving: 2700)
    end

    it "never holds a record" do
      create(:workout, user:, sport: running, distance: 5_000, moving_time: 1500, duration: 1600, pause_time: 100)

      create_entry(distance: 42_000.0, duration: 20_000, moving_time: 20_000)

      expect(Record.find_by(user:, sport: running, record_type: "FD").workout).to be_recording
    end

    it "refuses implausible figures, a maximum below the average, a future start and an unmeasured ascent" do
      fitness = catalog_sport("fitness")

      result = create_entry(sport: fitness, duration: 0, max_heart_rate: 100, started_at: 1.day.from_now,
                            calories: 50_000)

      expect(result).not_to be_success
      expect(result.workout.errors.details.transform_values { it.pluck(:error) }).to include(
        duration: [ :implausible ], max_heart_rate: [ :below_average ], started_at: [ :in_future ],
        calories: [ :implausible ], ascent: [ :not_for_sport ]
      )
      expect(Workout.manual_entries).to be_empty
    end

    it "refuses a moving time longer than the duration" do
      result = create_entry(moving_time: 4000)

      expect(result.workout.errors.of_kind?(:moving_time, :less_than_or_equal_to)).to be(true)
    end

    it "announces the new workout to webhooks" do
      allow(Webhooks::Events).to receive(:workout_created)

      result = create_entry

      expect(Webhooks::Events).to have_received(:workout_created).with(result.workout)
    end
  end

  describe "#call on an existing entry" do
    let(:entry) { create_entry(moving_time: nil).workout }

    it "changes only the given figures and keeps the moving time following the duration" do
      result = described_class.new(workout: entry).call({ duration: 3600 })

      expect(result).to be_success
      expect(entry.reload).to have_attributes(duration: 3600, moving_time: 3600, distance: 9_000)
      expect(result.changed).to contain_exactly("elapsed_time", "moving_time")
    end

    it "keeps a moving time the owner set apart" do
      entry.update!(moving_time: 2800, pause_time: 200)

      described_class.new(workout: entry).call({ duration: 3600 })

      expect(entry.reload).to have_attributes(duration: 3600, moving_time: 2800, pause_time: 800)
    end

    it "moves the totals of its equipment with its figures" do
      shoes = create(:equipment, user:)
      Equipments::Totals.sync(entry, [ shoes.id ])

      described_class.new(workout: entry).call({ distance: 12_000.0 }, equipment_ids: [ shoes.id ])

      expect(shoes.reload).to have_attributes(total_workouts: 1, total_distance: 12_000)
    end

    it "announces the changed fields" do
      allow(Webhooks::Events).to receive(:workout_updated)

      described_class.new(workout: entry).call({ title: "Sortie", calories: 650 })

      expect(Webhooks::Events).to have_received(:workout_updated).with(entry, contain_exactly("title", "calories"))
    end

    it "refuses a recording" do
      expect { described_class.new(workout: create(:workout, user:)) }.to raise_error(ArgumentError)
    end
  end

  describe "the database shape" do
    it "refuses a manual entry carrying a file digest or a position" do
      entry = create_entry.workout

      expect { Workout.transaction(requires_new: true) { entry.update_columns(source_digest: "a" * 64) } }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_manual_shape/)
      expect { Workout.transaction(requires_new: true) { entry.update_columns(points_count: 2) } }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_recording_shape/)
    end
  end

  describe "a sport change (Workouts::SportChange)" do
    it "changes a manual entry's sport without any file" do
      entry = create_entry.workout
      trail = catalog_sport("trail")

      Workouts::SportChange.new(workout: entry, sport: trail).call!

      expect(entry.reload.sport).to eq(trail)
    end

    it "refuses a sport that measures no elevation for an entry with an ascent" do
      entry = create_entry.workout

      expect { Workouts::SportChange.new(workout: entry, sport: catalog_sport("fitness")).call! }
        .to raise_error(Workouts::SportChange::ReanalysisFailed)
      expect(entry.reload.sport).to eq(running)
    end
  end
end
