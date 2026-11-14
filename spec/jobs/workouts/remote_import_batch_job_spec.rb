# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::RemoteImportBatchJob do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:connection) { create(:import_connection, :linked, user:) }
  let(:gpx) { Rails.root.join("spec/fixtures/gpx/galibier.gpx").binread }
  let(:galibier_start) { Time.utc(2026, 6, 1, 8) }
  let(:fallback) { catalog_sport("cycling") }
  let(:provider) { RemoteImportHelpers::FakeImportProvider.new(activities:, files:, errors:, fetch_attributes:, photos:) }
  let(:activities) { [] }
  let(:files) { {} }
  let(:errors) { {} }
  let(:fetch_attributes) { {} }
  let(:photos) { {} }

  around { |example| with_remote_import_enabled { example.run } }

  before do
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
    allow(ImportConnections::Providers).to receive(:for).with(connection).and_return(provider)
    connection.update!(fallback_sport: fallback)
  end

  def remote_batch(**attributes)
    create(:workout_import_batch, user:, sport: nil, source: "garmin_connect", import_connection: connection, **attributes)
  end

  it_behaves_like "an import provider" do
    let(:activities) { [ remote_activity(1, started_at: galibier_start) ] }
    let(:files) { { "1" => gpx } }
    let(:listed_activity) { activities.first }
  end

  context "with photos" do
    let(:activities) { [ remote_activity(1, started_at: galibier_start) ] }
    let(:files) { { "1" => gpx } }
    let(:photo_io) do
      Tempfile.new([ "remote-photo", ".jpg" ], binmode: true).tap do |io|
        io.write("\xFF\xD8\xFF\xE0".b)
        io.rewind
      end
    end
    let(:photos) do
      { "1" => Allure::RemoteImports::PhotoSet.new(
        listed: 2,
        photos: [ Allure::RemoteImports::Photo.new(io: photo_io, filename: "remote-photo.jpg") ]
      ) }
    end

    it "attaches the photos the provider offers and counts the one it could not fetch" do
      batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

      expect { described_class.perform_now(batch) }.to change(WorkoutPhoto, :count).by(1)

      workout = batch.entries.order(:position).first.workout
      expect(workout.photos.sole.original).to be_attached
      expect(batch.entries.order(:position).first.metadata)
        .to include("photos" => 1, "photos_missing" => 1)
    end

    it "attaches the photos of an interrupted run that committed the workout first" do
      batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))
      described_class.perform_now(batch)
      workout = batch.entries.order(:position).first.workout
      workout.photos.destroy_all
      entry = batch.entries.order(:position).first
      entry.update_columns(status: "processing", workout_id: nil, completed_at: nil)
      batch.update_columns(status: "processing", completed_at: nil)

      fresh = Tempfile.new([ "remote-photo", ".jpg" ], binmode: true)
      fresh.write("\xFF\xD8\xFF\xE0".b)
      fresh.rewind
      allow(provider).to receive(:photos).and_return(
        Allure::RemoteImports::PhotoSet.new(listed: 1, photos: [
          Allure::RemoteImports::Photo.new(io: fresh, filename: "remote-photo.jpg")
        ])
      )

      expect { described_class.perform_now(batch) }.to change(WorkoutPhoto, :count).by(1)
    end
  end

  context "with a date range" do
    let(:activities) do
      [
        remote_activity(1, started_at: galibier_start, name: "Galibier"),
        remote_activity(2, started_at: galibier_start + 3.hours, manual: true, name: "Manual entry"),
        remote_activity(3, started_at: Time.utc(2026, 7, 1, 8), name: "Outside the range")
      ]
    end
    let(:files) { { "1" => gpx } }
    let(:fetch_attributes) { { "1" => { title: "Col du Galibier", commute: true, device_name: "Edge 540" } } }

    it "lists the range in the owner's zone, skips a manual entry and imports the original" do
      batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

      expect { described_class.perform_now(batch) }.to change(Workout, :count).by(1)

      from, to = provider.listed_windows.sole
      expect(from).to eq(Time.find_zone("Europe/Paris").local(2026, 6, 1))
      expect(to).to eq(Time.find_zone("Europe/Paris").local(2026, 6, 30).end_of_day)

      batch.reload
      expect(batch).to have_attributes(status: "completed", total_entries: 2, imported_entries: 1, skipped_entries: 1,
                                       processed_entries: 2, discovered_at: be_present)
      imported, skipped = batch.entries.order(:position)
      expect(skipped).to have_attributes(status: "skipped", skip_reason: "no_file", external_id: "2")
      expect(provider.fetched).to eq([ "1" ])

      workout = imported.workout
      expect(workout).to have_attributes(import_connection: connection, external_id: "1", title: "Col du Galibier", commute: true)
      expect(workout.original_file.filename.to_s).to eq("remote-1.gpx")
      expect(imported.metadata).to include("device_name" => "Edge 540", "imported_title" => "Col du Galibier",
                                           "name" => "Galibier")
    end

    it "claims the workout an interrupted run created instead of calling it a duplicate of itself" do
      batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))
      described_class.perform_now(batch)
      entry = batch.entries.order(:position).first
      entry.update_columns(status: "processing", workout_id: nil, completed_at: nil)
      batch.update_columns(status: "processing", completed_at: nil)

      expect { described_class.perform_now(batch) }.not_to change(Workout, :count)

      expect(entry.reload).to have_attributes(status: "imported", workout_id: be_present)
      expect(batch.reload).to have_attributes(imported_entries: 1, duplicate_entries: 0)
    end

    context "with an indoor activity the provider lists without a polyline" do
      let(:activities) do
        [ remote_activity(9, started_at: galibier_start, geometry: false, sport_hint: "indoor_cycling", name: "Home trainer") ]
      end
      let(:files) { { "9" => File.read(tcx_fixture_path("indoor")) } }

      it "fetches it and imports it as a positionless recording" do
        batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

        expect { described_class.perform_now(batch) }.to change(Workout, :count).by(1)

        expect(provider.fetched).to eq([ "9" ])
        workout = batch.entries.sole.workout
        expect(workout).not_to be_positioned
        expect(workout.distance).to eq(5000.0)
        expect(workout.average_power).to be_present
      end
    end



    it "imports a manual retrieval as bulk and a scheduled sync as new outings" do
      flags = []
      allow(Workouts::Importer).to receive(:new).and_wrap_original do |original, **kwargs|
        flags << kwargs[:bulk]
        original.call(**kwargs)
      end

      described_class.perform_now(remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30)))
      expect(flags).to eq([ true ])

      Workout.find_each(&:destroy!)
      flags.clear
      batch = remote_batch(trigger: "scheduled", discovered_at: Time.current)
      Workouts::RemoteImportEntries.new(batch:, connection:).add([ activities.first ])
      described_class.perform_now(batch)
      expect(flags).to eq([ false ])
    end

    it "reports an activity the connection already imported as a duplicate without fetching it" do
      existing = create(:workout, user:, import_connection: connection, external_id: "1")
      batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

      expect { described_class.perform_now(batch) }.not_to change(Workout, :count)

      expect(batch.entries.find_by(external_id: "1")).to have_attributes(status: "duplicate", workout: existing)
      expect(provider.fetched).to be_empty
    end
  end

  context "with entries already discovered" do
    let(:activities) { [ remote_activity(1, started_at: galibier_start) ] }
    let(:files) { { "1" => gpx } }

    def discovered_batch
      remote_batch(trigger: "scheduled", discovered_at: Time.current).tap do |batch|
        Workouts::RemoteImportEntries.new(batch:, connection:).add(activities)
      end
    end

    it "treats a workout recorded at the same moment as a near duplicate" do
      other = create(:workout, user:, started_at: galibier_start + 90.seconds)

      batch = discovered_batch
      described_class.perform_now(batch)

      expect(batch.entries.sole).to have_attributes(status: "duplicate", workout: other)
      expect(provider.fetched).to be_empty
    end

    it "skips an activity without a file" do
      errors["1"] = Allure::RemoteImports::Error::NotFound.new("404")

      batch = discovered_batch
      described_class.perform_now(batch)

      expect(batch.entries.sole).to have_attributes(status: "skipped", skip_reason: "no_file")
    end

    it "skips an activity whose sport cannot be resolved" do
      connection.update!(fallback_sport: nil)

      batch = discovered_batch
      described_class.perform_now(batch)

      expect(batch.entries.sole).to have_attributes(status: "skipped", skip_reason: "unsupported_sport")
    end

    it "pauses on the quota and continues at the announced time" do
      retry_at = 10.minutes.from_now.change(usec: 0)
      errors["1"] = Allure::RemoteImports::Error::RateLimited.new("429", retry_at:)

      batch = discovered_batch
      expect { described_class.perform_now(batch) }.to have_enqueued_job(described_class).with(batch).at(retry_at)

      expect(batch.reload).to have_attributes(status: "processing", paused_until: retry_at)
      expect(batch.entries.sole.status).to eq("queued")
    end

    it "expires the connection and fails what remains when the token is refused" do
      errors["1"] = Allure::RemoteImports::Error::AuthError.new("401")

      batch = discovered_batch
      described_class.perform_now(batch)

      expect(connection.reload).to have_attributes(status: "expired", credentials: {})
      expect(batch.reload.status).to eq("completed")
      expect(batch.entries.sole).to have_attributes(status: "failed",
                                                     error_message: I18n.t("workouts.batch_import.errors.connection_expired"))
    end

    it "fails the entries of a connection that is no longer usable" do
      connection.update!(status: "expired")

      batch = discovered_batch
      described_class.perform_now(batch)

      expect(batch.reload.status).to eq("completed")
      expect(batch.entries.sole.status).to eq("failed")
      expect(provider.fetched).to be_empty
    end

    it "honours a cancellation" do
      batch = discovered_batch
      batch.cancel!
      described_class.perform_now(batch)

      expect(batch.reload.status).to eq("cancelled")
      expect(batch.entries.sole.status).to eq("cancelled")
    end

    it "gives up on a provider that stays unavailable" do
      errors["1"] = Allure::RemoteImports::Error::Unavailable.new("503")

      batch = discovered_batch
      perform_enqueued_jobs { described_class.perform_later(batch) }

      expect(provider.fetched.size).to eq(described_class::MAX_ATTEMPTS)
      expect(batch.reload.status).to eq("completed")
      expect(batch.entries.sole).to have_attributes(status: "failed",
                                                     error_message: I18n.t("workouts.batch_import.errors.provider_unavailable"))
    end
  end

  it "drops activities the connection already imported when the sync asks it" do
    create(:workout, user:, import_connection: connection, external_id: "7")
    batch = remote_batch(trigger: "scheduled")

    created = Workouts::RemoteImportEntries.new(batch:, connection:)
      .add([ remote_activity(7), remote_activity(8) ], drop_known: true)

    expect(created).to eq(1)
    expect(batch.entries.pluck(:external_id)).to eq([ "8" ])
  end

  context "when the provider's fetch names a declared sport" do
    let(:activities) { [ remote_activity(1, started_at: galibier_start) ] }
    let(:files) { { "1" => gpx } }
    let(:fetch_attributes) { { "1" => { declared_sport: "running" } } }

    it "imports through it, outranking the file's own detection" do
      running = catalog_sport("running")
      batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

      expect { described_class.perform_now(batch) }.to change(Workout, :count).by(1)

      expect(Workout.sole).to have_attributes(sport: running)
      expect(batch.entries.sole).to have_attributes(sport_source: "declared")
    end
  end

  context "when the connection imports positioned sessions only" do
    let(:connection) { create(:import_connection, :linked, user:, positioned_only: true) }

    it "skips an entry without a route as no_geometry before any fetch" do
      activities << remote_activity(1, started_at: galibier_start, geometry: false)
      activities << remote_activity(2, started_at: galibier_start + 1.hour)
      files["2"] = gpx
      batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

      expect { described_class.perform_now(batch) }.to change(Workout, :count).by(1)

      expect(provider.fetched).to eq([ "2" ])
      expect(batch.entries.order(:position).first).to have_attributes(status: "skipped", skip_reason: "no_geometry")
    end

    it "skips as no_geometry a session whose fetch carries no route" do
      activities << remote_activity(1, started_at: galibier_start)
      errors["1"] = Allure::RemoteImports::Error::NoGeometry.new("fewer than two location samples")
      batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

      expect { described_class.perform_now(batch) }.not_to change(Workout, :count)

      expect(batch.entries.sole).to have_attributes(status: "skipped", skip_reason: "no_geometry")
    end

    it "imports a route-less session when the flag is off" do
      connection.update!(positioned_only: false)
      activities << remote_activity(1, started_at: galibier_start, geometry: false)
      files["1"] = gpx
      batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

      expect { described_class.perform_now(batch) }.to change(Workout, :count).by(1)
    end
  end

  it "pauses for a reconnection when the provider's session ends naturally" do
    list_error = Allure::RemoteImports::Error::SessionEnded.new("the session expired")
    provider = RemoteImportHelpers::FakeImportProvider.new(list_error:)
    allow(ImportConnections::Providers).to receive(:for).with(connection).and_return(provider)
    batch = remote_batch(range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

    expect { described_class.perform_now(batch) }
      .not_to change(Notification, :count)

    expect(connection.reload).to have_attributes(status: "expired", credentials: be_empty)
    expect(batch.reload).to have_attributes(status: "queued", paused_until: nil)
  end
end
