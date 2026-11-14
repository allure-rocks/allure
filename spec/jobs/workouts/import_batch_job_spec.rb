# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ImportBatchJob do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }
  let(:gpx) { Rails.root.join("spec/fixtures/gpx/galibier.gpx").binread }
  let(:typed_gpx) { Rails.root.join("spec/fixtures/gpx/running_type.gpx").binread }
  let(:fit) { build_fit(points: simple_fit_points) }

  before do
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
  end

  def attach_source(batch, filename, content)
    batch.source_files.attach(io: StringIO.new(content), filename:, content_type: "application/octet-stream")
  end

  def zip_content(entries)
    Zip::OutputStream.write_buffer do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end.string
  end

  def gzip_content(content)
    buffer = StringIO.new
    Zlib::GzipWriter.wrap(buffer) { |gzip| gzip.write(content) }
    buffer.string
  end

  it "imports every GPX entry from a ZIP and preserves the individual originals" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "archive.zip", zip_content("one.gpx" => gpx, "two.gpx" => gpx.sub("Galibier", "Second")))

    expect { described_class.perform_now(batch) }.to change(Workout, :count).by(2)

    expect(batch.reload).to have_attributes(status: "completed", total_entries: 2, imported_entries: 2, processed_entries: 2)
    expect(batch.entries.order(:position).pluck(:status)).to eq([ "imported", "imported" ])
    expect(batch.entries.order(:position).map { |entry| entry.workout.original_file.filename.to_s }).to eq([ "one.gpx", "two.gpx" ])
  end

  it "passes the demo time shift through to every imported workout (PLAN_DEMO.md §4)" do
    other = create(:user)
    plain = create(:workout_import_batch, user: other, sport:)
    attach_source(plain, "archive.zip", zip_content("one.gpx" => gpx))
    described_class.perform_now(plain)

    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "archive.zip", zip_content("one.gpx" => gpx))
    described_class.perform_now(batch, time_shift: 86_400 * 195)

    shifted = batch.entries.first.workout
    expect(shifted.time_shift_seconds).to eq(86_400 * 195)
    expect(shifted.started_at).to eq(plain.entries.first.workout.started_at + 86_400 * 195)
  end

  it "claims the workout an interrupted run created, but never another entry's" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "archive.zip", zip_content("one.gpx" => gpx, "copy.gpx" => gpx))
    # An interrupted run never reached the end that releases the upload.
    allow(batch).to receive(:release_sources!)
    described_class.perform_now(batch)
    first, copy = batch.entries.order(:position)
    expect(copy.status).to eq("duplicate")
    first.update_columns(status: "processing", workout_id: nil, completed_at: nil)
    copy.update_columns(status: "processing", workout_id: nil, completed_at: nil)
    batch.update_columns(status: "processing", completed_at: nil)

    expect { described_class.perform_now(batch) }.not_to change(Workout, :count)

    expect(first.reload).to have_attributes(status: "imported", workout_id: be_present)
    expect(copy.reload).to have_attributes(status: "duplicate", workout_id: first.workout_id)
  end

  it "detects each entry independently and uses the batch sport as fallback" do
    running = catalog_sport("running")
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "archive.zip", zip_content("running.gpx" => typed_gpx, "fallback.gpx" => gpx))

    expect { described_class.perform_now(batch) }.to change(Workout, :count).by(2)

    workouts = batch.entries.order(:position).map(&:workout)
    expect(workouts.map(&:sport)).to eq([ running, sport ])
    expect(batch.entries.order(:position).pluck(:sport_source)).to eq([ "detected", "fallback" ])
  end

  it "imports mixed GPX and FIT entries and skips an exact duplicate" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(
      batch,
      "archive.zip",
      zip_content("one.gpx" => gpx, "two.fit" => fit, "duplicate.fit" => fit)
    )

    expect { described_class.perform_now(batch) }.to change(Workout, :count).by(2)

    expect(batch.reload).to have_attributes(status: "completed", total_entries: 3, imported_entries: 2, duplicate_entries: 1, processed_entries: 3)
    expect(batch.entries.order(:position).pluck(:status)).to eq([ "imported", "imported", "duplicate" ])
    expect(batch.entries.order(:position).map { |entry| entry.workout&.import_format }).to eq([ "gpx", "fit", "fit" ])
  end

  it "imports a gzip-compressed FIT source" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "ride.fit.gz", gzip_content(fit))

    expect { described_class.perform_now(batch) }.to change(Workout, :count).by(1)

    expect(batch.reload).to have_attributes(status: "completed", total_entries: 1, imported_entries: 1, processed_entries: 1)
    expect(batch.entries.first.workout).to have_attributes(import_format: "fit")
    expect(batch.entries.first.workout.original_file.filename.to_s).to eq("ride.fit")
  end

  it "applies the options card to every imported workout" do
    gear = create(:equipment, user:)
    batch = create(:workout_import_batch, user:, sport:, commute: true, equipments: [ gear ])
    attach_source(batch, "archive.zip", zip_content("one.gpx" => gpx, "two.gpx" => gpx.sub("Galibier", "Second")))

    expect { described_class.perform_now(batch) }.to change(Workout, :count).by(2)

    workouts = batch.entries.order(:position).map(&:workout)
    expect(workouts).to all(be_commute)
    expect(workouts.map(&:equipment_ids)).to eq([ [ gear.id ], [ gear.id ] ])
    expect(gear.reload.total_workouts).to eq(2)
  end

  it "titles the workout of a single-file import and ignores a batch title" do
    single = create(:workout_import_batch, user:, sport:, title: "Morning hike")
    attach_source(single, "ride.gpx", gpx)
    archive = create(:workout_import_batch, user:, sport:, title: "Batch title")
    attach_source(archive, "archive.zip", zip_content("one.gpx" => gpx, "two.gpx" => gpx.sub("Galibier", "Second")))

    described_class.perform_now(single)
    described_class.perform_now(archive)

    expect(single.entries.first.workout.title).to eq("Morning hike")
    archive_titles = archive.entries.order(:position).map { |entry| entry.workout.title }
    expect(archive_titles).to all(be_present)
    expect(archive_titles).not_to include("Batch title")
  end

  it "imports a gzip-compressed TCX whose declaration is preceded by whitespace" do
    tcx = "          " + Rails.root.join("spec/fixtures/tcx/normal.tcx").binread
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "ride.tcx.gz", gzip_content(tcx))

    expect { described_class.perform_now(batch) }.to change(Workout, :count).by(1)

    expect(batch.reload).to have_attributes(status: "completed", total_entries: 1, imported_entries: 1, processed_entries: 1)
    expect(batch.entries.first.workout).to have_attributes(import_format: "tcx")
    expect(batch.entries.first.workout.original_file.filename.to_s).to eq("ride.tcx")
  end

  it "imports TCX and KML entries from a ZIP plus a KMZ single source" do
    tcx = Rails.root.join("spec/fixtures/tcx/normal.tcx").binread
    kml = Rails.root.join("spec/fixtures/kml/normal.kml").binread
    # Distinct content so the KMZ is not an exact duplicate of the ZIP entry.
    kmz_kml = Rails.root.join("spec/fixtures/kml/with_altitude.kml").binread
    kmz = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("doc.kml")
      zip.write(kmz_kml)
    end.string
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "archive.zip", zip_content("one.tcx" => tcx, "two.kml" => kml))
    attach_source(batch, "track.kmz", kmz)

    expect { described_class.perform_now(batch) }.to change(Workout, :count).by(3)

    expect(batch.entries.order(:position).map { |entry| entry.workout.import_format }).to eq([ "tcx", "kml", "kml" ])
  end

  it "records an error raised before creating an entry" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "ride.gpx", gpx)
    job = described_class.new
    calls = 0
    allow(job).to receive(:next_position).and_wrap_original do |original, *args|
      calls += 1
      raise "entry setup failed" if calls == 1

      original.call(*args)
    end

    expect { job.perform(batch) }.not_to change(Workout, :count)

    expect(batch.reload).to have_attributes(status: "completed", total_entries: 1, failed_entries: 1)
    expect(batch.entries.first).to have_attributes(status: "failed", error_message: "entry setup failed")
  end

  it "continues after an invalid GPX and records the entry error" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "archive.zip", zip_content("valid.gpx" => gpx, "invalid.gpx" => "not gpx"))

    expect { described_class.perform_now(batch) }.to change(Workout, :count).by(1)

    expect(batch.reload).to have_attributes(status: "completed", imported_entries: 1, failed_entries: 1)
    expect(batch.entries.find_by(source_name: "invalid.gpx")).to have_attributes(status: "failed")
  end

  it "skips an exact duplicate for the same user" do
    digest = Digest::SHA256.hexdigest(gpx)
    existing = create(:workout, user:, sport:, source_digest: digest)
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "ride.gpx", gpx)

    expect { described_class.perform_now(batch) }.not_to change(Workout, :count)

    expect(batch.reload).to have_attributes(status: "completed", duplicate_entries: 1, processed_entries: 1)
    expect(batch.entries.first).to have_attributes(status: "duplicate", workout: existing)
  end

  it "cancels before processing any source" do
    batch = create(:workout_import_batch, user:, sport:, cancellation_requested_at: Time.current)
    attach_source(batch, "ride.gpx", gpx)

    expect { described_class.perform_now(batch) }.not_to change(Workout, :count)

    expect(batch.reload.status).to eq("cancelled")
  end

  it "keeps its history when an imported workout is deleted" do
    batch = create(:workout_import_batch, user:, sport:)
    workout = create(:workout, user:, sport:)
    entry = create(:workout_import_entry, batch:, workout:, status: "imported")

    workout.destroy!

    expect(entry.reload.workout).to be_nil
  end

  it "knows the full total before importing the first file" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "archive.zip", zip_content("one.gpx" => gpx, "two.gpx" => gpx.sub("Galibier", "Second")))
    observed = nil
    allow(Workouts::Importer).to receive(:new).and_wrap_original do |original, **kwargs|
      observed ||= batch.reload.attributes.slice("total_entries", "processed_entries")
      original.call(**kwargs)
    end

    described_class.perform_now(batch)

    expect(observed).to eq("total_entries" => 2, "processed_entries" => 0)
  end

  it "marks a batch above the automatic-publishing threshold as bulk" do
    small = create(:workout_import_batch, user:, sport:)
    attach_source(small, "archive.zip", zip_content("one.gpx" => gpx, "two.gpx" => gpx.sub("Galibier", "Second")))
    large = create(:workout_import_batch, user:, sport:)
    entries = (1..(WorkoutAutoPublication::BULK_FILE_ENTRIES + 1)).to_h { |index| [ "#{index}.gpx", gpx.sub("Galibier", "Ride #{index}") ] }
    attach_source(large, "large.zip", zip_content(entries))
    flags = []
    allow(Workouts::Importer).to receive(:new).and_wrap_original do |original, **kwargs|
      flags << kwargs[:bulk]
      original.call(**kwargs)
    end

    described_class.perform_now(small)
    expect(flags.uniq).to eq([ false ])

    flags.clear
    described_class.perform_now(large)
    expect(flags.uniq).to eq([ true ])
  end

  it "reports intermediate progress that never reaches 100 before the last file" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(
      batch,
      "archive.zip",
      zip_content(
        "one.gpx" => gpx,
        "two.gpx" => gpx.sub("Galibier", "Second"),
        "three.gpx" => gpx.sub("Galibier", "Third")
      )
    )
    percentages = []
    allow(Workouts::Importer).to receive(:new).and_wrap_original do |original, **kwargs|
      percentages << batch.reload.progress_percentage
      original.call(**kwargs)
    end

    described_class.perform_now(batch)

    expect(percentages).to eq([ 0, 33, 66 ])
    expect(batch.reload.progress_percentage).to eq(100)
    expect(batch).to have_attributes(status: "completed", processed_entries: 3)
  end

  it "fails the members a broken archive never reached without changing the total" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(
      batch,
      "archive.zip",
      zip_content("one.gpx" => gpx, "bad.gpx.gz" => gzip_content("not a track"))
    )

    described_class.perform_now(batch)

    expect(batch.reload).to have_attributes(
      status: "completed",
      total_entries: 2,
      imported_entries: 1,
      failed_entries: 1,
      processed_entries: 2
    )
    expect(batch.entries.order(:position).pluck(:status)).to eq([ "imported", "failed" ])
    expect(batch.progress_percentage).to eq(100)
  end

  it "refines a provisional gzip entry name from the extracted format" do
    batch = create(:workout_import_batch, user:, sport:)
    attach_source(batch, "ride.gpx.gz", gzip_content(fit))

    described_class.perform_now(batch)

    expect(batch.entries.first.source_name).to eq("ride.fit")
  end

  it "cancels entries discovered before the cancellation landed" do
    batch = create(:workout_import_batch, user:, sport:)
    create(:workout_import_entry, batch:, status: "queued", position: 0, source_key: "1:0")
    batch.update!(cancellation_requested_at: Time.current)

    described_class.perform_now(batch)

    expect(batch.reload).to have_attributes(
      status: "cancelled",
      total_entries: 1,
      cancelled_entries: 1,
      processed_entries: 1
    )
    expect(batch.entries.first.status).to eq("cancelled")
  end

  describe "the uploaded files (PLAN_IMPORT_SOURCES.md §3.2)" do
    it "frees them once the batch completes, the workouts keeping their own originals" do
      batch = create(:workout_import_batch, user:, sport:)
      attach_source(batch, "archive.zip", zip_content("one.gpx" => gpx))

      described_class.perform_now(batch)

      expect(batch.reload).to have_attributes(status: "completed")
      expect(batch.source_files).not_to be_attached
      expect(batch.entries.first.workout.original_file).to be_attached
    end

    it "frees them when the batch is cancelled or its only source is unreadable" do
      cancelled = create(:workout_import_batch, user:, sport:, cancellation_requested_at: Time.current)
      attach_source(cancelled, "ride.gpx", gpx)
      empty = create(:workout_import_batch, user:, sport:)
      attach_source(empty, "notes.zip", zip_content("readme.txt" => "nothing"))

      [ cancelled, empty ].each { described_class.perform_now(it) }

      expect(cancelled.reload).to have_attributes(status: "cancelled")
      expect(empty.reload).to have_attributes(status: "completed", failed_entries: 1)
      expect([ cancelled, empty ].map { it.source_files.attached? }).to all(be(false))
    end

    it "frees them when the batch fails on an unexpected error" do
      batch = create(:workout_import_batch, user:, sport:)
      attach_source(batch, "ride.gpx", gpx)
      allow(Workouts::ArchiveReader).to receive(:new).and_raise(RuntimeError, "boom")

      expect { described_class.perform_now(batch) }.to raise_error(RuntimeError, "boom")

      expect(batch.reload).to have_attributes(status: "failed")
      expect(batch.source_files).not_to be_attached
    end
  end

  it "runs one batch at a time per account" do
    batch = create(:workout_import_batch, user:, sport:)

    expect(described_class.new(batch).concurrency_key).to eq("WorkoutImportBatch/#{user.id}")
  end
end
