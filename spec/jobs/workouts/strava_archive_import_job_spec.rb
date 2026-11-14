# frozen_string_literal: true

require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe Workouts::StravaArchiveImportJob do
  let(:user) { create(:user) }
  let(:galibier) { Rails.root.join("spec/fixtures/gpx/galibier.gpx").binread }
  let(:running) { Rails.root.join("spec/fixtures/gpx/running_type.gpx").binread }

  before do
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
  end

  # Every GPX fixture starts on 2026-06-01; moving the day keeps the
  # near-duplicate window from joining distinct outings.
  def on_day(gpx, day) = gpx.gsub("2026-06-01T", format("2026-06-%02dT", day))

  def batch_with(files, sport: nil)
    batch = create(:workout_import_batch, user:, sport:, source: "strava_archive")
    batch.source_files.attach(io: StringIO.new(strava_archive_zip(files)), filename: "export_42.zip",
                              content_type: "application/zip")
    batch
  end

  def archive_files
    {
      "activities.csv" => strava_activities_csv([
        { id: 101, name: "Col du Galibier", type: "Ride", description: "Par le Télégraphe", note: "Genou ok",
          commute: true, gear: "Canyon", filename: "activities/9001.gpx.gz" },
        { id: 102, name: "Trail du matin", type: "Trail Run", gear: "Pegasus", filename: "activities/9002.gpx" },
        { id: 103, name: "Musculation", type: "Weight Training", date: "Jun 10, 2026, 6:00:00 PM", note: "Dos" },
        { id: 104, name: "Golf du dimanche", type: "Golf", filename: "activities/9004.gpx" },
        { id: 105, name: "Perdue", type: "Ride", filename: "activities/9005.gpx" }
      ]),
      "bikes.csv" => "Bike Name,Bike Brand,Bike Model\nCanyon,Canyon,Grail\n",
      "activities/9001.gpx.gz" => strava_gzip(galibier),
      "activities/9002.gpx" => on_day(running, 2),
      "activities/9004.gpx" => on_day(galibier, 4),
      "activities/9999.fit" => build_fit(points: simple_fit_points, sport: 2),
      "media/photo.jpg" => "not an image"
    }
  end

  it "imports each file with what the athlete wrote on Strava" do
    batch = batch_with(archive_files)

    expect { described_class.perform_now(batch) }.to change(user.workouts, :count).by(4)

    expect(batch.reload).to have_attributes(status: "completed", total_entries: 6, imported_entries: 4,
                                            skipped_entries: 2, failed_entries: 0)
    entries = batch.entries.order(:position)
    expect(entries.map(&:status)).to eq(%w[imported imported imported skipped skipped imported])
    expect(entries.map(&:skip_reason)).to eq([ nil, nil, nil, "unsupported_sport", "no_file", nil ])
    expect(entries.map(&:sport_source)).to eq(%w[declared declared declared unknown unknown detected])

    ride = entries.first.workout
    expect(ride).to have_attributes(title: "Col du Galibier", description: "Par le Télégraphe", notes: "Genou ok",
                                    commute: true)
    expect(ride.sport.slug).to eq("cycling")
    expect(ride.original_file.filename.to_s).to eq("9001.gpx")
    expect(ride.equipments.map(&:label)).to eq([ "Canyon" ])
    expect(ride.equipments.first).to have_attributes(description: "Canyon Grail")
    expect(ride.equipments.first.equipment_type.slug).to eq("bike")
    expect(Api::Rest::V1::WorkoutSerializer.new(ride, detail: true).as_json.deep_stringify_keys["import"])
      .to eq("source" => "strava_archive", "sport_source" => "declared")

    trail = entries.second.workout
    expect(trail.sport.slug).to eq("trail")
    expect(trail.equipments.first.equipment_type.slug).to eq("shoes")
    expect(entries.last.workout.sport.slug).to eq("cycling")
    expect(entries.map(&:source_name).first(3)).to eq([ "Col du Galibier", "Trail du matin", "Musculation" ])
    expect(entries.first.metadata["created_equipment"]).to eq("Canyon")
  end

  it "matches existing equipment by label and uses the fallback sport" do
    existing = create(:equipment, user:, label: "canyon")
    batch = batch_with(archive_files, sport: catalog_sport("hiking"))

    described_class.perform_now(batch)

    entries = batch.entries.order(:position)
    expect(entries.first.workout.equipments).to eq([ existing ])
    expect(entries.first.metadata).not_to have_key("created_equipment")
    golf = entries.fourth
    expect(golf).to have_attributes(status: "imported", sport_source: "fallback")
    expect(golf.workout.sport.slug).to eq("hiking")
  end

  it "refines a generic type with the account's default variant" do
    user.update!(default_cycling_sport: catalog_sport("cycling_road"))
    batch = batch_with(archive_files)

    described_class.perform_now(batch)

    expect(batch.entries.order(:position).first.workout.sport.slug).to eq("cycling_road")
  end

  it "creates nothing twice when the same archive is imported again" do
    described_class.perform_now(batch_with(archive_files))
    second = batch_with(archive_files)

    expect { described_class.perform_now(second) }
      .to not_change(user.workouts, :count).and(not_change(user.equipments, :count))
    expect(second.reload).to have_attributes(status: "completed", duplicate_entries: 4, imported_entries: 0)
  end

  it "treats a recording starting within two minutes as the same outing" do
    existing = create(:workout, user:, started_at: Time.utc(2026, 6, 2, 8, 1, 0))
    batch = batch_with(archive_files)

    described_class.perform_now(batch)

    expect(batch.entries.order(:position).second).to have_attributes(status: "duplicate", workout_id: existing.id)
  end

  describe "the mail at the end" do
    it "tells the account its archive is imported, once" do
      batch = batch_with(archive_files)

      expect { described_class.perform_now(batch) }
        .to have_enqueued_mail(ImportMailer, :strava_archive_finished).with(batch).once
    end

    it "tells it when the archive failed, never when it cancelled" do
      failed = batch_with({ "ride.gpx" => galibier })
      expect { described_class.perform_now(failed) }.to have_enqueued_mail(ImportMailer, :strava_archive_finished)

      cancelled = batch_with(archive_files)
      cancelled.update!(cancellation_requested_at: Time.current)
      expect { described_class.perform_now(cancelled) }.not_to have_enqueued_mail(ImportMailer, :strava_archive_finished)
    end

    it "sends nothing for a file batch" do
      batch = create(:workout_import_batch, user:, sport: catalog_sport("cycling"))
      batch.source_files.attach(io: StringIO.new(galibier), filename: "ride.gpx", content_type: "application/gpx+xml")

      expect { Workouts::ImportBatchJob.perform_now(batch) }.not_to have_enqueued_mail(ImportMailer)
    end
  end

  it "fails a ZIP that is not a Strava archive" do
    batch = batch_with({ "ride.gpx" => galibier })

    expect { described_class.perform_now(batch) }.not_to change(Workout, :count)

    expect(batch.reload).to have_attributes(status: "failed")
    expect(batch.error_message).to eq(I18n.t("workouts.batch_import.errors.not_strava_archive", locale: user.locale))
    expect(batch.source_files).not_to be_attached
  end

  it "frees the archive once it is imported" do
    batch = batch_with(archive_files)

    described_class.perform_now(batch)

    expect(batch.reload).to have_attributes(status: "completed")
    expect(batch.source_files).not_to be_attached
  end

  it "stops at a cancellation" do
    batch = batch_with(archive_files)
    batch.update!(cancellation_requested_at: Time.current)

    expect { described_class.perform_now(batch) }.not_to change(Workout, :count)

    expect(batch.reload).to have_attributes(status: "cancelled", cancelled_entries: 6)
  end

  describe "the archive's photos" do
    def files_with_photos
      archive_files.merge(
        "activities.csv" => strava_activities_csv([
          { id: 301, name: "Galibier", type: "Ride", filename: "activities/9001.gpx.gz",
            media: "media/one.jpg|media/missing.jpg|media/clip.mp4" },
          { id: 302, name: "Gainage", type: "Weight Training", date: "Jun 12, 2026, 7:00:00 PM", media: "media/two.jpg" }
        ]),
        "media.csv" => "Nom de fichier du support,Légende du support\nmedia/one.jpg,Au sommet\n",
        "media/one.jpg" => photo_bytes,
        "media/two.jpg" => photo_bytes,
        "media/clip.mp4" => "not a photo"
      )
    end

    it "attaches each listed photo, with its caption, to the workout its activity created" do
      batch = batch_with(files_with_photos)

      expect { described_class.perform_now(batch) }.to change(WorkoutPhoto, :count).by(2)

      ride, manual = batch.entries.order(:position).first(2)
      expect(ride.workout.photos.map(&:caption)).to eq([ "Au sommet" ])
      expect(ride.metadata).to include("photos" => 1, "photos_missing" => 1, "photos_refused" => 1)
      expect(manual.workout.photos.count).to eq(1)
    end

    it "finishes an entry an interrupted run left behind, photos included, without doubling them" do
      batch = batch_with(files_with_photos)
      # An interrupted run never reached the end that releases the upload.
      allow(batch).to receive(:release_sources!)
      described_class.perform_now(batch)
      ride, manual = batch.entries.order(:position).first(2)
      ride.workout.photos.destroy_all
      [ ride, manual ].each do |entry|
        entry.update_columns(status: "processing", workout_id: nil, completed_at: nil,
                             metadata: entry.metadata.except("photos", "photos_missing", "photos_refused"))
      end
      batch.update_columns(status: "processing", completed_at: nil)

      expect { described_class.perform_now(batch) }.not_to change(Workout, :count)

      expect(ride.reload).to have_attributes(status: "imported", sport_source: "declared")
      expect(ride.workout.photos.count).to eq(1)
      expect(manual.reload).to have_attributes(status: "imported", sport_source: "declared")
      expect(manual.workout.photos.count).to eq(1)
      expect(batch.reload).to have_attributes(duplicate_entries: 0)
    end

    it "attaches nothing to a duplicate or while photos are off" do
      described_class.perform_now(batch_with(files_with_photos))

      expect { described_class.perform_now(batch_with(files_with_photos)) }.not_to change(WorkoutPhoto, :count)
      with_photo_env("PHOTOS_ENABLED" => "false") do
        user.workouts.destroy_all
        expect { described_class.perform_now(batch_with(files_with_photos)) }.not_to change(WorkoutPhoto, :count)
      end
    end
  end

  describe "an activity typed in by hand on Strava" do
    it "becomes a manual entry with the row's figures" do
      batch = batch_with(archive_files)

      described_class.perform_now(batch)

      manual = batch.entries.order(:position).third.workout
      expect(manual).to have_attributes(origin: "manual", title: "Musculation", notes: "Dos", duration: 3600,
                                        moving_time: 3500, started_at: Time.utc(2026, 6, 10, 18, 0, 0))
      expect(manual.distance.to_f).to eq(10_000.0)
      expect(manual.sport.slug).to eq("strength_training")
    end

    it "refuses a date it cannot read, and a row without a type nor a fallback" do
      files = archive_files.merge("activities.csv" => strava_activities_csv([
        { id: 201, name: "Mystère", type: "Weight Training", date: "un mardi" },
        { id: 202, name: "Golf", type: "Golf", date: "Jun 11, 2026, 8:00:00 AM" }
      ]))
      batch = batch_with(files)

      described_class.perform_now(batch)

      first, second = batch.entries.order(:position).first(2)
      expect(first).to have_attributes(status: "failed", error_message: "Date Strava illisible : un mardi")
      expect(second).to have_attributes(status: "skipped", skip_reason: "unsupported_sport")
    end
  end

  it "resumes after discovery without listing the archive again" do
    batch = batch_with(archive_files)
    described_class.perform_now(batch)
    batch.update_columns(status: "processing", completed_at: nil)
    batch.entries.order(:position).first.update_columns(status: "queued", workout_id: nil)

    expect { described_class.perform_now(batch) }.not_to change(batch.entries, :count)
    expect(batch.reload.status).to eq("completed")
  end
end
