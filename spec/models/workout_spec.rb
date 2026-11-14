# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workout do
  include ActiveJob::TestHelper

  describe "identity" do
    it "receives a PostgreSQL UUID and exposes only its ShortUUID" do
      workout = create(:workout)

      expect(workout.uuid).to match(Allure::ShortId::UUID_PATTERN)
      expect(workout.to_param).to have_attributes(length: 22)
      # Asserting the exact encoding rather than "does not contain the id
      # digits": the base-57 alphabet includes 2-9, so a substring check
      # fails at random once the id sequence reaches a matching value.
      expect(workout.to_param).to eq(Allure::ShortId.encode(workout.uuid))
      expect(workout.to_param).not_to eq(workout.id.to_s)
      expect(described_class.find_by_short_id!(workout.to_param)).to eq(workout)
    end

    it "returns the same not-found error for malformed and unknown IDs" do
      expect { described_class.find_by_short_id!("invalid") }.to raise_error(ActiveRecord::RecordNotFound)
      expect { described_class.find_by_short_id!("2222222222222222222222") }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "treats the UUID as immutable" do
      workout = create(:workout)
      expect { workout.update!(uuid: SecureRandom.uuid) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    end
  end

  describe "import format" do
    it "accepts every format the importer can produce" do
      expect(described_class::IMPORT_FORMATS).to eq(%w[gpx fit tcx kml])
      expect(create(:workout, :fit).import_format).to eq("fit")
    end

    it "rejects an unknown format in the model" do
      workout = build(:workout, import_format: "txt")

      expect(workout).not_to be_valid
      expect(workout.errors[:import_format]).to be_present
    end

    # The model validation mirrors the database check rather than replacing
    # it, so a write that bypasses validation is still refused.
    it "rejects an unknown format in the database" do
      workout = create(:workout)

      expect { workout.update_column(:import_format, "txt") }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_import_format/)
    end
  end

  describe "elevation source" do
    it "defaults to the recording device" do
      expect(described_class.new.elevation_source).to eq("device")
      expect(described_class.new.elevation_source_requested).to be_nil
    end

    it "tracks whether the original file carried a profile" do
      expect(described_class.new.recorded_elevation).to be(false)
      expect(build(:workout)).to be_recorded_elevation
      expect(build(:workout, min_elevation: nil, max_elevation: nil)).not_to be_recorded_elevation
      expect(build(:workout, recorded_elevation: nil)).not_to be_valid
    end

    it "accepts device and dem, with an automatic request as nil" do
      expect(build(:workout, elevation_source: "dem", elevation_source_requested: "dem")).to be_valid
      expect(build(:workout, elevation_source_requested: nil)).to be_valid
      expect(build(:workout, elevation_source: "gps")).not_to be_valid
      expect(build(:workout, elevation_source_requested: "gps")).not_to be_valid
    end

    it "rejects an unknown source in the database" do
      workout = create(:workout)

      expect { workout.update_column(:elevation_source, "gps") }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_elevation_source/)
    end

    it "owns its terrain elevation row" do
      workout = create(:workout)
      elevation = create(:workout_elevation, workout:)

      expect(workout.reload.elevation).to eq(elevation)
      expect { workout.destroy! }.to change(WorkoutElevation, :count).by(-1)
    end
  end

  describe "commute" do
    it "defaults to false and only accepts booleans" do
      expect(described_class.new.commute).to be(false)
      expect(build(:workout, commute: true)).to be_valid
      expect(build(:workout, commute: nil)).not_to be_valid
    end

    it "is not a record source column" do
      expect(described_class::RECORD_SOURCE_COLUMNS).not_to include(:commute)
    end
  end

  describe "analysis version" do
    it "defaults new application records to the current analyzer version" do
      expect(build(:workout).analysis_version).to eq(Allure::Gpx::Analyzer::VERSION)
    end

    it "requires a positive version in the model and database" do
      expect(build(:workout, analysis_version: 0)).not_to be_valid

      workout = create(:workout)
      expect { workout.update_column(:analysis_version, 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_analysis_version/)
    end
  end

  describe ".visible_to" do
    it "returns published public workouts plus the viewer's own workouts" do
      viewer = create(:user)
      own = create(:workout, user: viewer)
      public_workout = create(:workout)
      create(:track_segment, workout: public_workout)
      profile = create(:publishing_profile, :without_endpoint_masks, user: public_workout.user)
      publish_workout!(user: public_workout.user, workout: public_workout, profile:)
      create(:workout)

      expect(described_class.visible_to(viewer)).to contain_exactly(own, public_workout)
      expect(described_class.visible_to(nil)).to be_empty
    end
  end

  describe "window scopes" do
    it "orders by proximity to a start, the oldest row on a tie" do
      reference = Time.zone.parse("2026-08-23 06:00:00")
      closer = create(:workout, started_at: reference + 10.minutes)
      tied = create(:workout, started_at: reference - 10.minutes)
      farther = create(:workout, started_at: reference - 2.hours)

      expect(described_class.ordered_by_start_proximity_to(reference))
        .to eq([ closer, tied, farther ])
    end

    it "keeps recordings whose duration reaches a moment" do
      reference = Time.zone.parse("2026-08-23 06:00:00")
      ending_after = create(:workout, started_at: reference - 30.minutes,
                                      duration: 3600, moving_time: 3500, pause_time: 100)
      ending_exactly = create(:workout, started_at: reference - 1.hour,
                                        duration: 3600, moving_time: 3500, pause_time: 100)
      create(:workout, started_at: reference - 2.hours, duration: 60)

      expect(described_class.ending_at_or_after(reference))
        .to contain_exactly(ending_after, ending_exactly)
    end
  end

  describe "#viewable_by?" do
    it "gives the owner access to every level" do
      workout = create(:workout)
      expect(%i[workout analysis map media]).to all(satisfy { workout.viewable_by?(workout.user, level: it) })
    end

    it "uses the active publication for signed-in public readers" do
      viewer = create(:user)
      workout = create(:workout)
      create(:track_segment, workout:)
      profile = create(:publishing_profile, :without_endpoint_masks, user: workout.user)
      publication = publish_workout!(user: workout.user, workout:, profile:)
      allow_any_instance_of(Workouts::MaplibreRouteImageRenderer).to receive(:call)
        .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "no browser")
      Workouts::RenderPublicationRouteImageJob.perform_now(publication)

      expect(workout.viewable_by?(viewer, level: :workout)).to be(true)
      expect(workout.viewable_by?(viewer, level: :analysis)).to be(true)
      expect(workout.viewable_by?(viewer, level: :map)).to be(true)
      # The default profile includes the sanitized route image.
      expect(workout.viewable_by?(viewer, level: :media)).to be(true)
    end

    it "never opens a public publication to an anonymous browser" do
      workout = create(:workout)
      create(:track_segment, workout:)
      profile = create(:publishing_profile, :without_endpoint_masks, user: workout.user)
      publish_workout!(user: workout.user, workout:, profile:)

      expect(workout.viewable_by?(nil, level: :workout)).to be(false)
    end
  end

  describe "database invariants" do
    it "round-trips the start geography in longitude/latitude order" do
      workout = create(:workout)
      workout.reload

      expect(workout.start_point).to be_a(RGeo::Feature::Point)
      expect([ workout.start_point.x, workout.start_point.y ]).to eq([ 6.4074, 45.071 ])
    end

    it "rejects inconsistent duration values below the model layer" do
      workout = create(:workout)
      expect { workout.update_columns(moving_time: 61, pause_time: -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_moving_time|workouts_pause_time/)
    end

    it "rejects negative physiological values below the model layer" do
      workout = create(:workout)
      expect { workout.update_column(:average_heart_rate, -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_physiological_metrics/)
    end

    it "has a GiST index for start-point queries" do
      index = described_class.connection.indexes(:workouts).find { it.columns == [ "start_point" ] }
      expect(index.using).to eq(:gist)
    end
  end

  # PLAN_TOGETHER.md §3.2: a credit row holds the credited metric set only.
  describe "credit rows" do
    let(:credit) { create(:workout, :credit) }

    it "is valid without location or file, and is not a recording" do
      expect(credit).to be_valid
      expect(credit).to be_credit
      expect(credit).not_to be_recording
      expect(credit.start_point).to be_nil
      expect(credit.import_format).to be_nil
      expect(described_class.credit_rows_only).to include(credit)
      expect(described_class.recordings).not_to include(credit)
    end

    it "still requires a file format and a point count on a recording" do
      workout = build(:workout, start_point: nil, bounds: nil, points_count: nil, import_format: nil)

      expect(workout).not_to be_valid
      expect(workout.errors).to include(:points_count, :import_format)
    end

    it "accepts a recording without a location, saved with both geometry columns empty" do
      workout = build(:workout, start_point: nil, bounds: nil)

      expect(workout).to be_valid
      expect(workout).not_to be_positioned
    end

    it "rejects a recording with a start point and no bounds" do
      workout = build(:workout, bounds: nil)

      expect(workout).not_to be_valid
      expect(workout.errors).to include(:bounds)
    end

    it "requires the source owner on a credit row" do
      credit.credited_by = nil

      expect(credit).not_to be_valid
      expect(credit.errors).to include(:credited_by)
    end

    it "rejects a recording whose location is half-cleared below the model layer" do
      workout = create(:workout)

      expect { workout.update_column(:start_point, nil) }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_recording_shape/)
    end

    it "rejects a credit row carrying a location below the model layer" do
      expect { credit.update_columns(bounds: [ 45.0, 6.4, 45.1, 6.5 ]) }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_recording_shape/)
    end

    it "rejects any excluded column on a credit row below the model layer" do
      credit_id = credit.id
      [
        { average_heart_rate: 140 }, { calories: 500 }, { source: "Garmin" },
        { description: "Notes" }, { commute: true }, { max_power: 300 },
        { places: [ "Meylan" ] }
      ].each do |attributes|
        expect {
          described_class.transaction(requires_new: true) { described_class.find(credit_id).update_columns(attributes) }
        }.to raise_error(ActiveRecord::StatementInvalid, /workouts_credit_shape/), attributes.inspect
      end
    end

    it "rejects credit columns on a recording below the model layer" do
      workout = create(:workout)

      expect { workout.update_column(:credited_max_climb, 120) }
        .to raise_error(ActiveRecord::StatementInvalid, /workouts_credit_shape/)
    end

    it "keeps one attached credit row per participant and source" do
      duplicate = build(:workout, :credit, user: credit.user, credited_from: credit.credited_from)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "is nullified, never blocked, when its source row disappears" do
      source = credit.credited_from
      described_class.where(id: source.id).delete_all

      expect(credit.reload.credited_from_workout_id).to be_nil
      expect(credit).to be_credit_detached
    end
  end

  describe "attachments" do
    it "uses authorized application endpoints instead of generic Active Storage routes" do
      expect(Rails.application.config.active_storage.draw_routes).to be(false)
      expect(described_class.reflect_on_attachment(:original_file)).to be_present
      expect(described_class.reflect_on_attachment(:route_image)).to be_present
    end

    it "purges attachment metadata and blobs after workout deletion" do
      workout = create(:workout)
      workout.original_file.attach(
        io: StringIO.new("<gpx version=\"1.1\" />"),
        filename: "workout.gpx",
        content_type: "application/gpx+xml"
      )
      workout.route_image.attach(
        io: StringIO.new("not-a-real-png"),
        filename: "route.png",
        content_type: "image/png"
      )
      blob_ids = [ workout.original_file.blob.id, workout.route_image.blob.id ]

      perform_enqueued_jobs { workout.destroy! }

      expect(ActiveStorage::Attachment.where(record: workout)).to be_empty
      expect(ActiveStorage::Blob.where(id: blob_ids)).to be_empty
    end
  end

  describe "records" do
    it "recomputes on create" do
      user = create(:user)
      sport = create(:sport)
      workout = create(:workout, user:, sport:, distance: 5000)

      expect(Record.find_by(user:, sport:, record_type: "FD")).to have_attributes(workout:, value: 5000)
    end

    it "reassigns both scopes on sport change" do
      user = create(:user)
      sport_a = create(:sport)
      sport_b = create(:sport)
      w1 = create(:workout, user:, sport: sport_a, distance: 1000)
      w2 = create(:workout, user:, sport: sport_a, distance: 2000)
      expect(Record.find_by(user:, sport: sport_a, record_type: "FD").workout).to eq(w2)

      w2.update!(sport: sport_b)

      expect(Record.find_by(user:, sport: sport_a, record_type: "FD").workout).to eq(w1)
      expect(Record.find_by(user:, sport: sport_b, record_type: "FD").workout).to eq(w2)
    end

    it "promotes the runner-up on delete" do
      user = create(:user)
      sport = create(:sport)
      w1 = create(:workout, user:, sport:, distance: 1000)
      w2 = create(:workout, user:, sport:, distance: 2000)

      w2.destroy!

      expect(Record.find_by(user:, sport:, record_type: "FD").workout).to eq(w1)
    end

    it "skips recompute on irrelevant edits but runs it on sport change" do
      workout = create(:workout)
      allow(Records::RecomputeService).to receive(:new).and_return(double(call: nil))

      workout.update!(title: "New title")
      expect(Records::RecomputeService).not_to have_received(:new)

      workout.update!(commute: true)
      expect(Records::RecomputeService).not_to have_received(:new)

      workout.update!(sport: create(:sport))
      expect(Records::RecomputeService).to have_received(:new).twice
    end
  end

  describe "equipment totals" do
    it "decrements attached equipment on destroy" do
      user = create(:user)
      equipment = create(:equipment, user:)
      workout = create(:workout, user:, distance: 1000, moving_time: 600, duration: 700, pause_time: 100)
      Equipments::Totals.sync(workout, [ equipment.id ])
      expect(equipment.reload.total_workouts).to eq(1)

      workout.destroy!

      expect(equipment.reload.total_workouts).to eq(0)
    end

    it "diffs attached equipment on metric change" do
      user = create(:user)
      equipment = create(:equipment, user:)
      workout = create(:workout, user:, distance: 1000, moving_time: 600, duration: 700, pause_time: 100)
      Equipments::Totals.sync(workout, [ equipment.id ])

      workout.update!(distance: 2000, moving_time: 900, duration: 1000, pause_time: 100)

      expect(equipment.reload.total_distance).to eq(2000)
      expect(equipment.reload.total_moving).to eq(900)
    end
  end

  describe "places" do
    it "accepts an empty or populated place array" do
      expect(build(:workout).places).to eq([])
      workout = build(:workout, places: [ { "name" => "Cimefroide", "kind" => "town" } ])

      expect(workout).to be_valid
    end

    it "rejects a non-array shape the database constraint also refuses" do
      workout = build(:workout, places: { "name" => "Cimefroide" })

      expect(workout).not_to be_valid
      expect(workout.errors).to include(:places)
    end
  end
end
