# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::Importer do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def uploaded_gpx(name)
    ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/#{name}.gpx")),
      filename: "#{name}.gpx",
      type: "application/gpx+xml"
    )
  end

  def importer(name = "multi_segment")
    described_class.new(user: user, sport: sport, uploaded_file: uploaded_gpx(name))
  end

  it "persists ordered segments, metrics, points, geometry, and the original file" do
    catalog_sport("cycling")
    result = importer.call

    expect(result).to be_success
    expect(result.workout).to have_attributes(
      user: user,
      sport: catalog_sport("cycling"),
      points_count: 6,
      analysis_version: Allure::Gpx::Analyzer::VERSION,
      elevation_filter: "barometric"
    )
    expect(result.workout.original_file).to be_attached
    expect(result.workout.active_publications.first).to be_nil
    expect(result.workout.track_segments.pluck(:position)).to eq([ 0, 1 ])
    expect(result.workout.track_segments).to all(have_attributes(points_count: 3))
    expect(result.workout.track_segments.map(&:points)).to all(be_an(Array))
    expect(result.workout.track_segments.map { it.geom.num_points }).to eq([ 3, 3 ])
    expect(result.workout.source_digest).to match(/\A\h{64}\z/)
  end

  describe "with a time shift (docs/dev/DEMO.md)" do
    let(:shift) { 86_400 * 195 }
    let(:other_user) { create(:user) }

    it "shifts every derived date and persists the offset for the re-analysis paths" do
      catalog_sport("cycling")
      bytes = build_fit(points: simple_fit_points, sport: 2,
                        laps: [ { time: Time.utc(2026, 5, 1, 8, 10), elapsed: 600 } ])

      unshifted = described_class.new(user: other_user, sport:, uploaded_file: fit_io(bytes), filename: "ride.fit").call.workout
      shifted = described_class.new(user:, sport:, uploaded_file: fit_io(bytes), filename: "ride.fit",
                                    time_shift: shift).call.workout

      expect(shifted.time_shift_seconds).to eq(shift)
      expect(shifted.started_at).to eq(unshifted.started_at + shift)
      # Durations never move: only the recording day does.
      expect(shifted.duration).to eq(unshifted.duration)
      expect(shifted.track_segments.pluck(:started_at))
        .to eq(unshifted.track_segments.pluck(:started_at).map { |started_at| started_at + shift })
      expect(shifted.laps.pluck(:started_at))
        .to eq(unshifted.laps.pluck(:started_at).map { |started_at| started_at + shift })
      # The stored original keeps the file's own dates; the shift is a fact
      # about the workout, not about the file.
      expect(shifted.original_file.blob.checksum).to eq(unshifted.original_file.blob.checksum)
    end

    it "leaves an ordinary import unshifted" do
      catalog_sport("cycling")

      workout = importer.call.workout

      expect(workout.time_shift_seconds).to eq(0)
    end
  end

  it "stores the heart-rate histogram with the workout (docs/dev/HEART-RATE.md)" do
    user.update!(max_heart_rate: 190)

    workout = importer("with_extensions").call.workout

    expect(workout.heart_rate_version).to eq(Allure::HeartRate::Histogram::VERSION)
    expect(workout.heart_rate.sampled_seconds).to be_positive
    expect(workout.heart_rate.zones_fingerprint).to eq(user.heart_rate_zones.fingerprint)
  end

  it "stamps the heart-rate marker without a row when the file has no heart rate" do
    catalog_sport("cycling")
    workout = importer.call.workout

    expect(workout.heart_rate_version).to eq(Allure::HeartRate::Histogram::VERSION)
    expect(workout.heart_rate).to be_nil
  end

  it "persists grade-adjusted pace for a pace sport with elevation" do
    catalog_sport("running")

    result = described_class.new(
      user: user,
      uploaded_file: uploaded_gpx("running_type"),
      sport: sport
    ).call

    expect(result.workout.grade_adjusted_pace).to be_a(Integer)
    expect(result.workout.track_segments).to all(have_attributes(grade_adjusted_pace: be_a(Integer)))
  end

  it "leaves grade-adjusted pace unset for a speed sport" do
    catalog_sport("cycling")

    expect(importer.call.workout.grade_adjusted_pace).to be_nil
  end

  it "uses the device's own elevation totals when the FIT session carries them" do
    bytes = build_fit(
      points: simple_fit_points,
      sport: 2,
      session_ascent: 123,
      session_descent: 45
    )

    result = described_class.new(
      user:,
      sport:,
      uploaded_file: fit_io(bytes),
      filename: "ride.fit"
    ).call

    expect(result).to be_success
    expect(result.workout.ascent).to eq(123.0)
    expect(result.workout.descent).to eq(45.0)
  end

  it "falls back to the computed ascent without device totals" do
    bytes = build_fit(points: simple_fit_points, sport: 2)

    result = described_class.new(
      user:,
      sport:,
      uploaded_file: fit_io(bytes),
      filename: "ride.fit"
    ).call

    expect(result).to be_success
    expect(result.workout.ascent).to eq(20.0)
    expect(result.workout.descent).to eq(0.0)
  end

  it "ignores a rendered world's session and lap totals" do
    # What Zwift writes: an ascent with no descent in the session, and zeros in
    # the lap that covers the whole ride. The computed profile is the truth.
    bytes = build_fit(
      points: simple_fit_points,
      sport: 2,
      sub_sport: 58,
      session_ascent: 80,
      session_descent: 0,
      laps: [ { time: Time.utc(2026, 5, 1, 8, 3, 0), elapsed: 180, distance: 400, ascent: 0, descent: 0 } ]
    )

    result = described_class.new(
      user:,
      sport: catalog_sport("cycling_virtual"),
      uploaded_file: fit_io(bytes),
      filename: "zwift.fit"
    ).call

    expect(result).to be_success
    expect(result.workout.sport.slug).to eq("cycling_virtual")
    expect(result.workout.ascent).to eq(20.0)
    expect(result.workout.descent).to eq(0.0)
  end

  it "persists a FIT commuting sub sport as a commute" do
    catalog_sport("cycling")
    bytes = build_fit(points: simple_fit_points, sport: 2, sub_sport: 48)

    result = described_class.new(
      user:,
      sport:,
      uploaded_file: fit_io(bytes),
      filename: "commute.fit"
    ).call

    expect(result).to be_success
    expect(result.workout).to be_commute
    expect(result.workout.sport.slug).to eq("cycling")
  end

  it "defaults commute to false without a file hint or an owner flag" do
    catalog_sport("cycling")

    expect(importer.call.workout).not_to be_commute
  end

  it "honours the owner's explicit commute flag" do
    catalog_sport("cycling")
    result = described_class.new(
      user:, sport:, uploaded_file: uploaded_gpx("multi_segment"), commute: true
    ).call

    expect(result.workout).to be_commute
  end

  it "leaves the elevation filter unset when the file carries no elevation" do
    catalog_sport("running")

    result = described_class.new(
      user: user,
      uploaded_file: uploaded_gpx("no_elevation"),
      sport: sport
    ).call

    expect(result.workout.elevation_filter).to be_nil
  end

  it "treats zero placeholders in a partial profile as no recorded elevation" do
    catalog_sport("running")

    result = described_class.new(
      user: user,
      uploaded_file: uploaded_gpx("zero_placeholders"),
      sport: sport
    ).call

    expect(result.workout).to have_attributes(
      recorded_elevation: false,
      min_elevation: nil,
      max_elevation: nil,
      elevation_filter: nil
    )
  end

  it "persists best efforts and their records for an imported pace workout" do
    catalog_sport("running")

    result = described_class.new(
      user: user,
      uploaded_file: uploaded_gpx("running_5k"),
      sport: sport
    ).call

    expect(result).to be_success
    expect(result.workout.best_efforts.find_by(distance_key: "km1").duration_seconds).to eq(100)
    expect(result.workout.best_efforts.find_by(distance_key: "km5").duration_seconds).to eq(500)
    expect(EffortRecord.find_by(user:, sport: result.workout.sport, distance_key: "km5").duration_seconds).to eq(500)
  end

  it "uses the detected sport instead of the selected fallback" do
    detected_sport = catalog_sport("running")

    result = described_class.new(
      user: user,
      uploaded_file: uploaded_gpx("running_type"),
      sport: sport
    ).call

    expect(result).to be_success
    expect(result.workout.sport).to eq(detected_sport)
    expect(result.sport_source).to eq("detected")
  end

  it "imports with no fallback when the GPX contains a recognized activity" do
    detected_sport = catalog_sport("running")

    result = described_class.new(
      user: user,
      uploaded_file: uploaded_gpx("running_type"),
      sport: nil
    ).call

    expect(result).to be_success
    expect(result.workout.sport).to eq(detected_sport)
    expect(result.sport_source).to eq("detected")
  end

  it "uses the account's default variant for a detected generic sport" do
    catalog_sport("running")
    preferred = catalog_sport("trail")
    user.update!(default_running_sport: preferred)

    result = described_class.new(
      user: user,
      uploaded_file: uploaded_gpx("running_type"),
      sport: sport
    ).call

    expect(result).to be_success
    expect(result.workout.sport).to eq(preferred)
    expect(result.sport_source).to eq("detected")
  end

  it "keeps an explicit detection even when a generic default is set" do
    catalog_sport("cycling")
    preferred = catalog_sport("cycling_road")
    detected = catalog_sport("mountain_biking")
    user.update!(default_cycling_sport: preferred)

    result = described_class.new(
      user: user,
      uploaded_file: fit_io(build_fit(points: simple_fit_points, sport: 2, sub_sport: 8)),
      sport: sport,
      filename: "mtb.fit"
    ).call

    expect(result).to be_success
    expect(result.workout.sport).to eq(detected)
    expect(result.sport_source).to eq("detected")
  end

  it "does not map the fallback sport" do
    preferred = catalog_sport("cycling_road")
    fallback = catalog_sport("cycling")
    user.update!(default_cycling_sport: preferred)

    result = described_class.new(
      user: user,
      uploaded_file: uploaded_gpx("galibier"),
      sport: fallback
    ).call

    expect(result).to be_success
    expect(result.workout.sport).to eq(fallback)
    expect(result.sport_source).to eq("fallback")
  end

  it "reports an exact duplicate for the same user" do
    expect(importer("galibier").call).to be_success

    duplicate = importer("galibier").call

    expect(duplicate).to be_failure
    expect(duplicate).to be_duplicate
    expect(duplicate.errors).to eq([ "est une copie exacte d'une activité existante" ])
  end

  it "reports a recording starting within the near-duplicate window as the same outing" do
    existing = create(:workout, user:, started_at: Time.utc(2026, 6, 1, 8, 1, 30))
    importer = described_class.new(user:, sport:, uploaded_file: uploaded_gpx("galibier"),
                                   near_duplicate_window: 120.seconds)

    result = nil
    expect { result = importer.call }.not_to change(Workout, :count)
    expect(result).to be_duplicate
    expect(result.workout).to eq(existing)
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it "ignores nearby recordings without a near-duplicate window" do
    create(:workout, user:, started_at: Time.utc(2026, 6, 1, 8, 1, 30))

    expect(importer("galibier").call).to be_success
  end

  it "rolls back all rows and purges the blob when a segment write fails" do
    writes = 0
    allow_any_instance_of(TrackSegment).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
      writes += 1
      raise ActiveRecord::RecordInvalid, method.receiver if writes == 2

      method.call(*args, **kwargs)
    end

    expect { importer.call }.not_to change(ActiveStorage::Blob, :count)
    expect(Workout.count).to eq(0)
    expect(TrackSegment.count).to eq(0)
    expect(ActiveStorage::Attachment.count).to eq(0)
  end

  it "rolls back all rows and purges the blob when attachment metadata fails" do
    error = ActiveRecord::RecordInvalid.new(ActiveStorage::Attachment.new)
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_raise(error)

    expect { importer.call }.not_to change(ActiveStorage::Blob, :count)
    expect(Workout.count).to eq(0)
    expect(TrackSegment.count).to eq(0)
    expect(ActiveStorage::Attachment.count).to eq(0)
  end

  it "purges the persisted blob row when storage upload fails" do
    allow(ActiveStorage::Blob.service).to receive(:upload).and_raise("storage unavailable")

    expect { importer.call }.to raise_error(RuntimeError, "storage unavailable")
    expect(ActiveStorage::Blob.count).to eq(0)
    expect(Workout.count).to eq(0)
  end

  it "enqueues route-image generation only after the transaction commits" do
    outer_transactions = Workout.connection.open_transactions
    stub_const("Workouts::RenderRouteImageJob", Class.new do
      def self.perform_later(*) = nil
    end)

    expect(Workouts::RenderRouteImageJob).to receive(:perform_later) do |workout|
      expect(workout).to be_persisted
      expect(Workout.connection.open_transactions).to eq(outer_transactions)
    end

    expect(importer("galibier").call).to be_success
  end

  it "enqueues segment matching only after the transaction commits" do
    outer_transactions = Workout.connection.open_transactions
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)

    expect(Segments::MatchWorkoutJob).to receive(:perform_later) do |workout|
      expect(workout).to be_persisted
      expect(Workout.connection.open_transactions).to eq(outer_transactions)
    end

    expect(importer("galibier").call).to be_success
  end

  it "enqueues recurring-route detection for a positioned recording" do
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
    allow(Together::DetectWorkoutJob).to receive(:perform_later)
    allow(Workouts::EnrichToponymyJob).to receive(:perform_later)

    expect(Segments::SuggestRouteJob).to receive(:perform_later) do |workout|
      expect(workout).to be_persisted
    end

    expect(importer("galibier").call).to be_success
  end

  it "skips the per-recording route-suggestion pass for a bulk import" do
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
    allow(Together::DetectWorkoutJob).to receive(:perform_later)
    allow(Workouts::EnrichToponymyJob).to receive(:perform_later)

    expect(Segments::SuggestRouteJob).not_to receive(:perform_later)

    described_class.new(user:, sport:, uploaded_file: uploaded_gpx("galibier"), bulk: true).call
  end

  it "enqueues toponymy enrichment only after the transaction commits" do
    outer_transactions = Workout.connection.open_transactions
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)

    expect(Workouts::EnrichToponymyJob).to receive(:perform_later) do |workout|
      expect(workout).to be_persisted
      expect(Workout.connection.open_transactions).to eq(outer_transactions)
    end

    expect(importer("galibier").call).to be_success
  end

  it "names the virtual venue and never enqueues geocoding for a virtual platform file" do
    catalog_sport("rowing_virtual")
    points = [
      { time: Time.utc(2026, 5, 1, 8, 0, 0), lat: 51.545, lon: -0.885, altitude: 20.0 },
      { time: Time.utc(2026, 5, 1, 8, 1, 0), lat: 51.5452, lon: -0.8848, altitude: 20.0 },
      { time: Time.utc(2026, 5, 1, 8, 2, 0), lat: 51.5454, lon: -0.8846, altitude: 20.0 }
    ]
    bytes = build_fit(points:, sport: 15, sub_sport: 14, product_name: nil,
                      manufacturer: 255, product: 22, serial_number: 1234)
    allow(Workouts::EnrichToponymyJob).to receive(:perform_later)

    result = described_class.new(user:, sport: nil, uploaded_file: fit_upload(bytes)).call

    expect(result).to be_success
    expect(result.workout.source).to eq("EXR")
    expect(result.workout.sport.slug).to eq("rowing_virtual")
    expect(result.workout.places).to eq([ { "name" => "Henley", "kind" => "virtual_venue" } ])
    expect(Workouts::EnrichToponymyJob).not_to have_received(:perform_later)
  end

  it "enqueues terrain elevation for an elevation-less workout of an opted-in account" do
    allow(Allure::Elevation::Config).to receive(:configured?).and_return(true)
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
    allow(Workouts::EnrichToponymyJob).to receive(:perform_later)
    user.update!(elevation_enrichment_enabled: true)

    expect(Workouts::ApplyElevationSourceJob).to receive(:perform_later) do |workout, source|
      expect(workout).to be_persisted
      expect(workout.min_elevation).to be_nil
      expect(source).to eq("dem")
    end

    result = importer("no_elevation").call
    expect(result).to be_success
    # The pending request is what automatic publishing waits on.
    expect(result.workout.reload.elevation_source_requested).to eq("dem")
  end

  it "defers geocoding to the terrain re-analysis, leaving a pending toponymy" do
    allow(Allure::Elevation::Config).to receive(:configured?).and_return(true)
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
    allow(Workouts::ApplyElevationSourceJob).to receive(:perform_later)
    user.update!(elevation_enrichment_enabled: true)

    expect(Workouts::EnrichToponymyJob).not_to receive(:perform_later)

    result = importer("no_elevation").call
    expect(result).to be_success
    expect(result.workout.reload.toponymy).to be_pending
  end

  it "marks the toponymy pending when it schedules geocoding" do
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
    allow(Workouts::EnrichToponymyJob).to receive(:perform_later)

    result = importer("galibier").call

    expect(result.workout.reload.toponymy).to be_pending
    expect(Workouts::EnrichToponymyJob).to have_received(:perform_later).with(result.workout)
  end

  describe "automatic publishing" do
    let!(:profile) { create(:publishing_profile, user:, auto_publish: true, auto_publish_acknowledged: true) }

    before do
      allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
      allow(Segments::MatchWorkoutJob).to receive(:perform_later)
      allow(Workouts::EnrichToponymyJob).to receive(:perform_later)
    end

    it "records the automatic publication of a new workout" do
      result = described_class.new(user:, sport:, uploaded_file: uploaded_gpx("galibier")).call

      rows = result.workout.auto_publications
      expect(rows.map(&:publishing_profile)).to eq([ profile ])
      # The fixture was recorded long ago: the recent window rules it out.
      expect(rows.first).to have_attributes(status: "skipped", reason: "stale")
    end

    it "never publishes a bulk import" do
      result = described_class.new(user:, sport:, uploaded_file: uploaded_gpx("galibier"), bulk: true).call

      expect(result.workout.auto_publications.first).to have_attributes(status: "skipped", reason: "bulk_import")
    end

    it "keeps the import when the enrollment fails" do
      allow_any_instance_of(Workouts::AutoPublicationEnrollment).to receive(:call).and_raise("boom")

      expect(described_class.new(user:, sport:, uploaded_file: uploaded_gpx("galibier")).call).to be_success
    end
  end

  it "does not enqueue terrain elevation for a recorded profile" do
    allow(Allure::Elevation::Config).to receive(:configured?).and_return(true)
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
    allow(Workouts::EnrichToponymyJob).to receive(:perform_later)
    user.update!(elevation_enrichment_enabled: true)

    expect(Workouts::ApplyElevationSourceJob).not_to receive(:perform_later)

    expect(importer("galibier").call).to be_success
  end

  it "does not enqueue terrain elevation when the account did not opt in" do
    allow(Allure::Elevation::Config).to receive(:configured?).and_return(true)
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
    allow(Workouts::EnrichToponymyJob).to receive(:perform_later)

    expect(Workouts::ApplyElevationSourceJob).not_to receive(:perform_later)

    expect(importer("no_elevation").call).to be_success
  end

  it "keeps a committed workout when route-image enqueueing fails" do
    allow(Workouts::RenderRouteImageJob).to receive(:perform_later).and_raise("queue unavailable")

    result = importer("galibier").call

    expect(result).to be_success
    expect(result.workout.reload).to be_persisted
    expect(result.workout.original_file).to be_attached
  end

  it "localizes invalid track-point errors" do
    allow_any_instance_of(Allure::Gpx::Parser).to receive(:parse)
      .and_raise(Allure::Gpx::InvalidPointError, "malformed latitude")

    I18n.with_locale(:fr) do
      expect(importer("galibier").call.errors).to eq([ "contient un point de trace invalide" ])
    end
  end

  describe "upload validation" do
    def upload(content, filename: "ride.gpx")
      described_class.new(
        user:, sport:, uploaded_file: StringIO.new(content.b), filename:
      ).call
    end

    it "rejects a missing file before anything else" do
      result = described_class.new(user:, sport:, uploaded_file: nil).call

      expect(result).to be_failure
      expect(result.errors).to eq([ "doit être sélectionné" ])
    end

    it "rejects an unsupported extension" do
      result = upload("<gpx></gpx>", filename: "ride.txt")

      expect(result.errors).to include("n'est pas un fichier GPX, FIT, TCX ou KML pris en charge")
    end

    it "rejects a filename with no extension" do
      result = upload("<gpx></gpx>", filename: "ride")

      expect(result.errors).to include("doit avoir une extension .gpx, .fit, .tcx ou .kml")
    end

    it "rejects content matching no supported format" do
      result = upload("PK\x03\x04 not a track at all")

      expect(result.errors).to include("n'est pas un fichier GPX, FIT, TCX ou KML pris en charge")
    end

    it "rejects a file above the size limit" do
      result = upload("<gpx>#{'x' * described_class::MAX_BYTES}</gpx>")

      expect(result.errors).to include("est trop volumineux (max 25 Mo)")
    end

    it "accepts any uploaded content type, because browsers report FIT inconsistently" do
      file = ActionDispatch::Http::UploadedFile.new(
        tempfile: File.open(Rails.root.join("spec/fixtures/gpx/galibier.gpx")),
        filename: "galibier.gpx",
        type: "application/x-whatever"
      )

      expect(described_class.new(user:, sport:, uploaded_file: file).call).to be_success
    end
  end

  describe "FIT imports" do
    def fit_importer(bytes, filename: "ride.fit", **options)
      described_class.new(
        user:, sport:, uploaded_file: fit_io(bytes), filename:, **options
      )
    end

    it "persists a workout with the fit import format and its own blob metadata" do
      result = fit_importer(build_fit(points: simple_fit_points, calories: 420, enhanced_max_speed: 12.5)).call

      expect(result).to be_success
      workout = result.workout
      expect(workout.import_format).to eq("fit")
      expect(workout.points_count).to eq(3)
      expect(workout.calories).to eq(420)
      expect(workout.max_speed).to eq(12.5)
      expect(workout.source).to eq("Allure Test Device")
      expect(workout.original_file.content_type).to eq("application/vnd.ant.fit")
      expect(workout.original_file.filename.to_s).to eq("ride.fit")
      expect(workout.track_segments.pluck(:position)).to eq([ 0 ])
    end

    it "stores the original bytes unchanged so the download round-trips" do
      bytes = build_fit(points: simple_fit_points)

      workout = fit_importer(bytes).call.workout

      expect(workout.original_file.download.b).to eq(bytes.b)
    end

    it "persists a recording segment per timer stop_all event" do
      points = (0..5).map do
        { time: Time.utc(2026, 5, 1, 8, it, 0), lat: 45.0 + (it * 0.001), lon: 6.0 + (it * 0.001) }
      end

      workout = fit_importer(build_fit(points:, stops: [ Time.utc(2026, 5, 1, 8, 3, 0) ])).call.workout

      expect(workout.track_segments.pluck(:position)).to eq([ 0, 1 ])
      expect(workout.track_segments.pluck(:points_count)).to eq([ 3, 3 ])
    end

    it "selects the sport from the FIT sport enumeration rather than the fallback" do
      detected = catalog_sport("mountain_biking")

      result = fit_importer(build_fit(points: simple_fit_points, sport: 2, sub_sport: 8)).call

      expect(result.workout.sport).to eq(detected)
      expect(result.sport_source).to eq("detected")
    end

    it "falls back to the selected sport for an activity outside the catalog" do
      result = fit_importer(build_fit(points: simple_fit_points, sport: 32)).call

      expect(result.workout.sport).to eq(sport)
      expect(result.sport_source).to eq("fallback")
    end

    it "titles the workout from sport and date, since FIT carries no track name" do
      result = fit_importer(build_fit(points: simple_fit_points)).call

      expect(result.workout.title).to be_present
      expect(result.workout.title_source).to eq("default")
      expect(result.workout.description).to be_nil
    end

    it "keeps a title typed by the member and stamps it as theirs" do
      result = fit_importer(build_fit(points: simple_fit_points), title: "Ma sortie").call

      expect(result.workout).to have_attributes(title: "Ma sortie", title_source: "owner")
    end

    it "detects FIT content even when the file claims to be a GPX" do
      result = fit_importer(build_fit(points: simple_fit_points), filename: "mislabelled.gpx").call

      expect(result).to be_success
      expect(result.workout.import_format).to eq("fit")
      expect(result.workout.original_file.filename.to_s).to eq("mislabelled.fit")
    end

    it "localizes a corrupt FIT file" do
      result = fit_importer(build_fit(points: simple_fit_points, corrupt_crc: true)).call

      expect(result).to be_failure
      expect(result.errors).to eq([ "est un fichier FIT corrompu ou illisible" ])
    end

    it "localizes a FIT file that is not an activity" do
      result = fit_importer(build_fit(points: simple_fit_points, file_type: :course)).call

      expect(result).to be_failure
      expect(result.errors).to eq([ "est un fichier FIT qui ne contient pas d'activité" ])
    end

    it "reports an exact duplicate of a previously imported FIT file" do
      bytes = build_fit(points: simple_fit_points)
      expect(fit_importer(bytes).call).to be_success

      expect(fit_importer(bytes).call).to be_duplicate
    end
  end

  describe "recorded laps" do
    it "persists the laps recorded in a three-lap GPX" do
      result = importer("three_laps_recorded").call

      expect(result).to be_success
      expect(result.workout.laps.length).to eq(3)
      expect(result.workout.laps.map(&:number)).to eq([ 1, 2, 3 ])
      expect(result.workout.laps.map { |l| l.distance }).to eq([ 405.0, 405.0, 405.0 ])
      # GPX carries no lap-trigger concept, so the column stays nil.
      expect(result.workout.laps).to all(have_attributes(lap_trigger: nil))
    end

    it "persists no laps for a file that recorded none" do
      expect(importer("galibier").call.workout.laps).to be_empty
    end

    it "persists the laps of a lapped FIT with their recovered metrics" do
      points = (0..17).map do |i|
        { time: Time.utc(2026, 5, 1, 8, 0, 0) + (i * 30), lat: 45.0 + (i % 4) * 0.0005, lon: 6.0 + (i % 4) * 0.0006 }
      end
      result = described_class.new(
        user:, sport:, uploaded_file: fit_io(build_fit(points:, laps: [
          { time: Time.utc(2026, 5, 1, 8, 1, 30), elapsed: 90, moving: 80, distance: 405, avg_heart_rate: 140, lap_trigger: 0 },
          { time: Time.utc(2026, 5, 1, 8, 3, 0), elapsed: 90, moving: 85, distance: 380, avg_heart_rate: 150, lap_trigger: 1 },
          { time: Time.utc(2026, 5, 1, 8, 4, 30), elapsed: 90, moving: 70, distance: 410, avg_heart_rate: 155, lap_trigger: 2 }
        ])), filename: "ride.fit"
      ).call
      expect(result).to be_success, result.errors.join("; ")
      workout = result.workout

      expect(workout.laps.length).to eq(3)
      expect(workout.laps.map(&:number)).to eq([ 1, 2, 3 ])
      expect(workout.laps.map { |l| l.average_heart_rate }).to eq([ 140, 150, 155 ])
      expect(workout.laps.map { |l| l.lap_trigger }).to eq([ "manual", "distance", "time" ])
    end

    it "cascades the laps when the workout is destroyed" do
      workout = importer("three_laps_recorded").call.workout

      expect { workout.destroy! }.to change(Lap, :count).by(-3)
    end
  end

  describe "TCX imports" do
    def tcx_upload(name, filename: "#{name}.tcx")
      ActionDispatch::Http::UploadedFile.new(
        tempfile: File.open(Rails.root.join("spec/fixtures/tcx/#{name}.tcx")),
        filename: filename,
        type: "application/vnd.garmin.tcx+xml"
      )
    end

    def tcx_upload_with_prologue(name, prologue: "          ")
      content = prologue + File.read(Rails.root.join("spec/fixtures/tcx/#{name}.tcx"))
      tempfile = Tempfile.new([ "prologue-#{name}", ".tcx" ])
      tempfile.write(content)
      tempfile.rewind
      ActionDispatch::Http::UploadedFile.new(tempfile:, filename: "#{name}.tcx",
                                            type: "application/vnd.garmin.tcx+xml")
    end

    it "persists a workout with the tcx import format, metrics, and laps" do
      running = catalog_sport("running")

      result = described_class.new(user:, sport:, uploaded_file: tcx_upload("with_laps")).call

      expect(result).to be_success
      workout = result.workout
      expect(workout.import_format).to eq("tcx")
      expect(workout.sport).to eq(running)
      expect(result.sport_source).to eq("detected")
      expect(workout.points_count).to eq(13)
      expect(workout.laps.length).to eq(3)
      expect(workout.laps.map(&:number)).to eq([ 1, 2, 3 ])
      expect(workout.original_file.content_type).to eq("application/vnd.garmin.tcx+xml")
      expect(workout.original_file.filename.to_s).to eq("with_laps.tcx")
    end

    it "imports a TCX whose declaration is preceded by whitespace" do
      running = catalog_sport("running")

      result = described_class.new(user:, sport:, uploaded_file: tcx_upload_with_prologue("normal")).call

      expect(result).to be_success, result.errors.join("; ")
      expect(result.workout.sport).to eq(running)
      expect(result.workout.points_count).to eq(3)
    end

    it "logs the malformed XML detail while keeping the localized error" do
      allow(Rails.logger).to receive(:warn)

      result = described_class.new(user:, sport:, uploaded_file: tcx_upload("malformed")).call

      expect(result).to be_failure
      expect(result.errors).to eq([ I18n.t("workouts.import.errors.malformed") ])
      expect(Rails.logger).to have_received(:warn).with(a_string_including("malformed XML", "malformed.tcx"))
    end

    it "never lets the file name forge a log line" do
      logged = []
      allow(Rails.logger).to receive(:warn) { logged << it }
      upload = tcx_upload("malformed", filename: "ride.tcx\nI, [2026-10-24] INFO -- : admin signed in\r\e[31m\u2028x.tcx")

      described_class.new(user:, sport:, uploaded_file: upload).call

      expect(logged.sole).not_to match(/[\r\n\e\u2028]/)
      expect(logged.sole).to include("ride.tcx I, [2026-10-24] INFO -- : admin signed in")
    end

    it "detects TCX content even when the file claims to be a GPX" do
      result = described_class.new(user:, sport:, uploaded_file: tcx_upload("normal", filename: "mislabelled.gpx")).call

      expect(result).to be_success
      expect(result.workout.import_format).to eq("tcx")
      expect(result.workout.original_file.filename.to_s).to eq("mislabelled.tcx")
    end

    it "localizes a TCX file with no track" do
      result = described_class.new(user:, sport:, uploaded_file: tcx_upload("unsupported")).call

      expect(result).to be_failure
      expect(result.errors).to eq([ I18n.t("workouts.import.errors.no_track") ])
    end
  end

  describe "KML imports" do
    def kml_upload(name, filename: "#{name}.kml")
      ActionDispatch::Http::UploadedFile.new(
        tempfile: File.open(Rails.root.join("spec/fixtures/kml/#{name}.kml")),
        filename: filename,
        type: "application/vnd.google-earth.kml+xml"
      )
    end

    it "persists a workout with the kml import format and no laps" do
      running = catalog_sport("running")

      result = described_class.new(user:, sport:, uploaded_file: kml_upload("normal")).call

      expect(result).to be_success
      workout = result.workout
      expect(workout.import_format).to eq("kml")
      expect(workout.sport).to eq(running)
      expect(result.sport_source).to eq("detected")
      expect(workout.points_count).to eq(3)
      expect(workout.laps).to be_empty
      expect(workout.original_file.content_type).to eq("application/vnd.google-earth.kml+xml")
      expect(workout.original_file.filename.to_s).to eq("normal.kml")
    end

    it "localizes a KML file with no timed track" do
      result = described_class.new(user:, sport:, uploaded_file: kml_upload("no_points")).call

      expect(result).to be_failure
      expect(result.errors).to eq([ I18n.t("workouts.import.errors.no_track") ])
    end
  end

  describe "equipment" do
    it "persists links and totals when equipment IDs are supplied" do
      equipment = create(:equipment, user:)

      result = described_class.new(user:, sport:, uploaded_file: uploaded_gpx("galibier"),
        equipment_ids: [ equipment.id ]).call

      expect(result).to be_success
      expect(result.workout.equipment_ids).to eq([ equipment.id ])
      expect(equipment.reload.total_workouts).to eq(1)
      expect(equipment.total_distance).to be > 0
    end

    it "persists no links when equipment IDs are absent" do
      result = described_class.new(user:, sport:, uploaded_file: uploaded_gpx("galibier")).call

      expect(result).to be_success
      expect(result.workout.equipment_ids).to be_empty
    end
  end

  describe "text a file hands on (docs/dev/WORKOUT.md)" do
    def uploaded_text(content, filename)
      file = Tempfile.new([ "importer-", File.extname(filename) ])
      file.write(content)
      file.rewind
      ActionDispatch::Http::UploadedFile.new(tempfile: file, filename:, type: "application/octet-stream")
    end

    it "clips an over-long device name, title and description instead of refusing the file" do
      gpx = Rails.root.join("spec/fixtures/gpx/galibier.gpx").read
        .sub('creator="Allure Test Suite"', %(creator="#{'D' * 300}"))
        .sub("<name>Col du Galibier</name>", "<name>#{'N' * 300}</name>")
        .sub("<desc>Normal timed 3D route with known metrics</desc>", "<desc>#{'d' * 12_000}</desc>")

      result = described_class.new(user:, sport:, uploaded_file: uploaded_text(gpx, "long.gpx")).call

      expect(result).to be_success
      expect(result.workout).to have_attributes(source: "D" * 255, title: "N" * 255, title_source: "file",
                                              description: "d" * 10_000)
    end

    it "clips an over-long lap trigger" do
      tcx = Rails.root.join("spec/fixtures/tcx/normal.tcx").read
        .sub("<TriggerMethod>Manual</TriggerMethod>", "<TriggerMethod>#{'x' * 500}</TriggerMethod>")

      result = described_class.new(user:, sport:, uploaded_file: uploaded_text(tcx, "laps.tcx")).call

      expect(result).to be_success
      expect(result.workout.laps.first.lap_trigger).to eq("x" * Allure::Gpx::TextLimits::LAP_TRIGGER)
    end
  end

  it "reports a database refusal instead of showing its text" do
    error = ActiveRecord::StatementInvalid.new(%(PG::CheckViolation: ERROR: new row for relation "workouts"))
    allow_any_instance_of(Workout).to receive(:save!).and_raise(error)
    allow(Rails.error).to receive(:report)

    result = importer.call

    expect(result).not_to be_success
    expect(result.errors).to eq([ I18n.t("workouts.import.errors.not_saved") ])
    expect(result.errors.join).not_to include("PG::")
    expect(Rails.error).to have_received(:report).with(error, hash_including(handled: true))
  end
end
