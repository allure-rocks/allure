# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::MatchWorkoutJob do
  before do
    allow(Segments::BackfillSegmentJob).to receive(:perform_later)
  end

  it "schedules the assistant summary once the efforts are settled" do
    workout = create(:workout)
    create(:track_segment, workout:)
    allow(Workouts::SummaryRefresh).to receive(:schedule)

    described_class.perform_now(workout)

    expect(Workouts::SummaryRefresh).to have_received(:schedule).with(workout)
  end

  it "persists owner efforts and updates segment counters" do
    workout = create(:workout)
    create(:track_segment, workout:)
    segment = create(:segment, user: workout.user, sport: workout.sport)

    described_class.perform_now(workout)

    effort = SegmentEffort.find_by!(segment:, workout:)
    expect(effort).to have_attributes(
      occurrence_index: 0,
      elapsed_time: 60,
      moving_time: 60,
      matcher_version: Allure::Segments::Matcher::VERSION,
      user: workout.user,
      sport: workout.sport
    )
    expect(segment.reload).to have_attributes(efforts_count: 1, athletes_count: 1)
  end

  it "persists integer HR/power maxima when interpolation produces floats" do
    workout = create(:workout)
    create(:track_segment, workout:,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0, "hr" => 140, "pw" => 200 },
        { "t" => 60, "d" => 250.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 112.0, "hr" => 150, "pw" => 210 }
      ])
    segment = create(:segment, user: workout.user, sport: workout.sport)

    described_class.perform_now(workout)

    effort = SegmentEffort.find_by!(segment:, workout:)
    expect(effort.max_heart_rate).to be_an(Integer)
    expect(effort.max_power).to be_an(Integer)
    expect(effort.average_heart_rate).to be_an(Integer)
    expect(effort.average_power).to be_an(Integer)
  end

  it "is idempotent and preserves the existing effort row" do
    workout = create(:workout)
    create(:track_segment, workout:)
    segment = create(:segment, user: workout.user, sport: workout.sport)

    described_class.perform_now(workout)
    effort_id = SegmentEffort.find_by!(segment:, workout:).id
    described_class.perform_now(workout)

    expect(SegmentEffort.where(segment:, workout:).pluck(:id)).to eq([ effort_id ])
  end

  it "rebuilds an effort with a stale matcher version" do
    workout = create(:workout)
    create(:track_segment, workout:)
    segment = create(:segment, user: workout.user, sport: workout.sport)
    effort = create(:segment_effort, workout:, segment:)
    effort.update_column(:matcher_version, 0)

    described_class.perform_now(workout)

    expect(SegmentEffort.find_by!(segment:, workout:).matcher_version).to eq(Allure::Segments::Matcher::VERSION)
  end

  it "persists a single end-to-end effort on a route" do
    workout = create(:workout)
    create(:track_segment, workout:)
    route = create(:segment, :route, user: workout.user, sport: workout.sport)

    described_class.perform_now(workout)

    effort = SegmentEffort.find_by!(segment: route, workout:)
    expect(effort).to have_attributes(occurrence_index: 0, matcher_version: Allure::Segments::Matcher::VERSION)
    expect(route.reload).to have_attributes(efforts_count: 1, athletes_count: 1)
  end

  # The importer enqueues one match while an elevation reanalysis or a segment
  # backfill can enqueue another for the same workout; the row lock makes them
  # run one after the other instead of racing the unique effort key.
  it "locks the workout row so concurrent matches serialize" do
    workout = create(:workout)
    create(:track_segment, workout:)
    create(:segment, user: workout.user, sport: workout.sport)

    lock_statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      lock_statements << payload[:sql] if payload[:sql].include?("FOR UPDATE")
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.perform_now(workout)
    end

    expect(lock_statements).to include(a_string_matching(/FROM "workouts".*FOR UPDATE/))
  end

  # A segment backfill fans out one job per candidate workout; an account's
  # jobs share its segments and loops, so they run one at a time.
  it "runs one match at a time per account" do
    workout = create(:workout)

    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.new(workout).concurrency_key)
      .to eq("Segments::MatchWorkoutJob/segments-match-#{workout.user_id}")
  end

  # The refresh rewrites every athlete's efforts on a segment; inside the
  # matching transaction, two matches of one segment deadlocked on each
  # other's efforts.
  it "refreshes the matched segments after the matching transaction" do
    workout = create(:workout)
    create(:track_segment, workout:)
    first = create(:segment, user: workout.user, sport: workout.sport)
    second = create(:segment, user: workout.user, sport: workout.sport)
    baseline = ActiveRecord::Base.connection.open_transactions
    refreshes = []
    allow(Segments::Refresh).to receive(:call).and_wrap_original do |original, segment|
      refreshes << [ segment.id, ActiveRecord::Base.connection.open_transactions ]
      original.call(segment)
    end

    described_class.perform_now(workout)

    expect(refreshes).to eq([ [ first.id, baseline ], [ second.id, baseline ] ])
    expect(first.reload).to have_attributes(efforts_count: 1, athletes_count: 1)
    expect(SegmentEffort.find_by!(segment: first, workout:).personal_best).to be(true)
  end

  it "skips a candidate segment deleted after the candidates were read" do
    workout = create(:workout)
    create(:track_segment, workout:)
    segment = create(:segment, user: workout.user, sport: workout.sport)
    candidates = [ segment ]
    candidates.define_singleton_method(:find_each) { |&block| each(&block) }
    allow(Segments::CandidateQuery).to receive(:for_workout).and_return(candidates)
    Segment.where(id: segment.id).delete_all

    expect { described_class.perform_now(workout) }.not_to raise_error
    expect(SegmentEffort.where(workout:)).to be_empty
  end

  it "takes a key-share lock on each segment before writing its efforts" do
    workout = create(:workout)
    create(:track_segment, workout:)
    create(:segment, user: workout.user, sport: workout.sport)

    statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] if payload[:sql].match?(/FOR KEY SHARE|INSERT INTO "segment_efforts"/)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.perform_now(workout)
    end

    expect(statements.first).to match(/FROM "segments".*FOR KEY SHARE/)
    expect(statements).to include(a_string_matching(/INSERT INTO "segment_efforts"/))
  end

  describe "personal best" do
    it "awards the badge to the earlier start on an elapsed-time tie" do
      user = create(:user)
      sport = create(:sport)
      segment = create(:segment, user:, sport:)
      workout1 = create(:workout, user:, sport:, started_at: Time.zone.parse("2026-08-23 06:00:00"))
      workout2 = create(:workout, user:, sport:, started_at: Time.zone.parse("2026-08-23 07:00:00"))
      create(:track_segment, workout: workout1)
      create(:track_segment, workout: workout2)

      described_class.perform_now(workout1)
      described_class.perform_now(workout2)

      expect(SegmentEffort.find_by!(segment:, workout: workout1).personal_best).to be(true)
      expect(SegmentEffort.find_by!(segment:, workout: workout2).personal_best).to be(false)
    end

    it "moves the badge to a faster effort and holds it on re-run" do
      user = create(:user)
      sport = create(:sport)
      segment = create(:segment, user:, sport:)
      workout1 = create(:workout, user:, sport:)
      create(:track_segment, workout: workout1)
      workout2 = create(:workout, user:, sport:)
      create(:track_segment, workout: workout2,
        points: [
          { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
          { "t" => 30, "d" => 250.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 112.0 }
        ],
        duration: 30, moving_time: 30, pause_time: 0)

      described_class.perform_now(workout1)
      expect(SegmentEffort.find_by!(segment:, workout: workout1).personal_best).to be(true)

      described_class.perform_now(workout2)
      expect(SegmentEffort.find_by!(segment:, workout: workout2).personal_best).to be(true)
      expect(SegmentEffort.find_by!(segment:, workout: workout1).personal_best).to be(false)

      described_class.perform_now(workout2)
      expect(SegmentEffort.find_by!(segment:, workout: workout2).personal_best).to be(true)
      expect(SegmentEffort.find_by!(segment:, workout: workout1).personal_best).to be(false)
    end

    it "keeps one personal best per sport on an all-sports segment" do
      user = create(:user)
      cyclist = create(:sport)
      runner = create(:sport)
      segment = create(:segment, user:, sport: nil)
      ride = create(:workout, user:, sport: cyclist)
      run = create(:workout, user:, sport: runner)
      create(:track_segment, workout: ride)
      create(:track_segment, workout: run)

      described_class.perform_now(ride)
      described_class.perform_now(run)

      expect(SegmentEffort.find_by!(segment:, workout: ride).personal_best).to be(true)
      expect(SegmentEffort.find_by!(segment:, workout: run).personal_best).to be(true)
    end

    it "awards each athlete their own badge on a shared segment, not only its creator" do
      sport = create(:sport)
      owner = create(:user)
      athlete = create(:user)
      segment = create(:segment, user: owner, sport:, visibility: "public")
      owner_workout = create(:workout, user: owner, sport:)
      athlete_workout = create(:workout, user: athlete, sport:)
      create(:track_segment, workout: owner_workout)
      create(:track_segment, workout: athlete_workout)

      described_class.perform_now(owner_workout)
      described_class.perform_now(athlete_workout)

      expect(SegmentEffort.find_by!(segment:, workout: owner_workout).personal_best).to be(true)
      expect(SegmentEffort.find_by!(segment:, workout: athlete_workout).personal_best).to be(true)
    end
  end

  describe "loop detection" do
    def import_fixture(user, sport, filename)
      file = ActionDispatch::Http::UploadedFile.new(
        tempfile: File.open(Rails.root.join("spec/fixtures/gpx/#{filename}")),
        filename:,
        type: "application/gpx+xml"
      )
      Workouts::Importer.new(user:, sport:, uploaded_file: file).call.workout
    end

    def import_three_laps(user, sport)
      import_fixture(user, sport, "three_laps.gpx")
    end

    # The recorded fixture covers the same circuit with a different digest.
    def import_three_recorded_laps(user, sport)
      import_fixture(user, sport, "three_laps_recorded.gpx")
    end

    it "persists a private loop segment with three efforts for a three-lap workout" do
      user = create(:user)
      sport = create(:sport)
      workout = import_three_laps(user, sport)

      described_class.perform_now(workout)

      loop_segment = Segment.find_by!(source_workout: workout, kind: "loop")
      expect(loop_segment).to have_attributes(
        user:, sport:, visibility: "private", active: true
      )
      expect(loop_segment.segment_efforts.order(:occurrence_index).pluck(:occurrence_index)).to eq([ 0, 1, 2 ])
      expect(loop_segment.reload).to have_attributes(efforts_count: 3, athletes_count: 1)
      expect(workout.reload.loop_reuse_version).to eq(Segments::LoopReuse::VERSION)
    end

    def add_approach_and_return(workout)
      segment = workout.track_segments.sole
      points = segment.points
      start = points.first
      approach = start.merge("lon" => start.fetch("lon") - 0.003, "d" => 0.0, "t" => 0)
      shifted = points.map { |point| point.merge("d" => point.fetch("d") + 300, "t" => point.fetch("t") + 100) }
      finish = approach.merge("d" => shifted.last.fetch("d") + 300, "t" => shifted.last.fetch("t") + 100)
      segment.update!(points: [ approach ] + shifted + [ finish ], points_count: points.length + 2,
        distance: finish.fetch("d"), duration: finish.fetch("t"), moving_time: finish.fetch("t"), pause_time: 0)
    end

    it "finds three complete tours between an approach and return and remains idempotent" do
      workout = import_three_laps(create(:user), create(:sport))
      add_approach_and_return(workout)

      described_class.perform_now(workout)

      loop_segment = Segment.find_by!(source_workout: workout, kind: "loop")
      expect(loop_segment.source_start_index).to eq(1)
      efforts = loop_segment.segment_efforts.order(:occurrence_index)
      expect(efforts.count).to eq(3)
      expect(efforts.first.start_point_index).to be >= 1
      expect(efforts.last.end_point_index).to be < workout.track_segments.sole.points.length - 1
      ids = efforts.pluck(:id)

      described_class.perform_now(workout)

      expect(loop_segment.segment_efforts.order(:occurrence_index).pluck(:id)).to eq(ids)
      expect(Segment.where(kind: "loop").count).to eq(1)
    end

    it "does not close a circuit across a recording gap" do
      workout = import_three_laps(create(:user), create(:sport))
      segment = workout.track_segments.sole
      points = segment.points.first(5)
      segment.update!(points: points.first(3), points_count: 3)
      create(:track_segment, workout:, position: 1, points: points.last(2), points_count: 2)

      described_class.perform_now(workout)

      expect(Segment.where(kind: "loop")).to be_empty
    end

    it "reuses an existing similar loop from another workout of the account" do
      user = create(:user)
      sport = create(:sport)
      first = import_three_laps(user, sport)
      described_class.perform_now(first)
      loop_segment = Segment.find_by!(source_workout: first, kind: "loop")

      second = import_three_recorded_laps(user, sport)
      allow(Allure::Segments::Matcher).to receive(:new).and_call_original
      described_class.perform_now(second)

      expect(Segment.where(kind: "loop").pluck(:id)).to eq([ loop_segment.id ])
      expect(loop_segment.segment_efforts.where(workout: second).count).to eq(3)
      expect(loop_segment.reload.efforts_count).to eq(6)
      # Once to validate the reused geometry, once to persist full metrics;
      # rotated discovery candidates must not re-match the same stored loop.
      expect(Allure::Segments::Matcher).to have_received(:new).with(hash_including(segment: loop_segment)).twice
    end

    def keep_one_tour(workout, reverse: false, partial: false)
      track = workout.track_segments.sole
      points = track.points.first(partial ? 4 : 5)
      coordinates = reverse ? points.reverse : points
      points = points.each_with_index.map do |point, index|
        point.merge(coordinates[index].slice("lat", "lon"))
      end
      track.update!(points:, points_count: points.length)
    end

    it "recognizes a known loop once after an approach, without discovery, and preserves its effort on rerun" do
      user = create(:user)
      sport = create(:sport)
      first = import_three_laps(user, sport)
      described_class.perform_now(first)
      loop_segment = Segment.find_by!(source_workout: first, kind: "loop")
      second = import_three_recorded_laps(user, sport)
      keep_one_tour(second)
      add_approach_and_return(second)
      allow(Allure::Geometry::LoopCandidates).to receive(:new)
        .and_return(instance_double(Allure::Geometry::LoopCandidates, ranked: []))

      described_class.perform_now(second)

      effort = second.segment_efforts.find_by!(segment: loop_segment)
      expect(second.segment_efforts.count).to eq(1)
      expect(second.detected_laps.where(source: "loop").count).to eq(1)
      expect(effort.start_point_index).to eq(1)
      expect(effort.end_point_index).to eq(5)
      expect(loop_segment.reload.efforts_count).to eq(4)

      described_class.perform_now(second)

      expect(second.segment_efforts.find_by!(segment: loop_segment).id).to eq(effort.id)
      expect(Segment.where(kind: "loop").pluck(:id)).to eq([ loop_segment.id ])
      expect(second.reload.loop_reuse_version).to eq(Segments::LoopReuse::VERSION)
    end

    it "refuses reversed and incomplete single traversals of a known loop" do
      user = create(:user)
      sport = create(:sport)
      first = import_three_laps(user, sport)
      described_class.perform_now(first)

      second = import_three_recorded_laps(user, sport)
      keep_one_tour(second, reverse: true)
      described_class.perform_now(second)
      expect(second.segment_efforts).to be_empty

      keep_one_tour(second, partial: true)
      described_class.perform_now(second)
      expect(second.segment_efforts).to be_empty
      expect(second.detected_laps.where(source: "loop")).to be_empty
    end

    it "never recognizes another account's private loop from a single traversal" do
      sport = create(:sport)
      first = import_three_laps(create(:user), sport)
      described_class.perform_now(first)
      second = import_three_recorded_laps(create(:user), sport)
      keep_one_tour(second)

      described_class.perform_now(second)

      expect(second.segment_efforts).to be_empty
      expect(Segment.where(kind: "loop").count).to eq(1)
    end

    it "does not recognize an inactive known loop from a single traversal" do
      user = create(:user)
      sport = create(:sport)
      first = import_three_laps(user, sport)
      described_class.perform_now(first)
      Segment.find_by!(kind: "loop").update!(active: false)
      second = import_three_recorded_laps(user, sport)
      keep_one_tour(second)

      described_class.perform_now(second)

      expect(second.segment_efforts).to be_empty
    end

    it "refuses a known-loop traversal that crosses a recording gap" do
      user = create(:user)
      sport = create(:sport)
      first = import_three_laps(user, sport)
      described_class.perform_now(first)
      second = import_three_recorded_laps(user, sport)
      track = second.track_segments.sole
      points = track.points.first(5)
      track.update!(points: points.first(3), points_count: 3)
      create(:track_segment, workout: second, position: 1, points: points.last(2), points_count: 2)

      described_class.perform_now(second)

      expect(second.segment_efforts).to be_empty
      expect(second.detected_laps.where(source: "loop")).to be_empty
    end

    it "widens a reused loop to all sports when the sports differ" do
      user = create(:user)
      rower = create(:sport)
      runner = create(:sport)
      first = import_three_laps(user, rower)
      described_class.perform_now(first)

      second = import_three_recorded_laps(user, runner)
      described_class.perform_now(second)

      loop_segment = Segment.find_by!(kind: "loop")
      expect(loop_segment.sport_id).to be_nil
      expect(loop_segment.segment_efforts.pluck(:sport_id).uniq).to contain_exactly(rower.id, runner.id)
    end

    it "creates a distinct loop for a different circuit" do
      user = create(:user)
      sport = create(:sport)
      first = import_three_laps(user, sport)
      described_class.perform_now(first)
      first_loop = Segment.find_by!(source_workout: first, kind: "loop")

      second = import_three_recorded_laps(user, sport)
      track_segment = second.track_segments.sole
      track_segment.update!(points: track_segment.points.map { |point| point.merge("lon" => point.fetch("lon") + 0.5) })

      described_class.perform_now(second)

      loops = Segment.where(kind: "loop").order(:id)
      expect(loops.count).to eq(2)
      expect(loops.first).to eq(first_loop)
      expect(loops.last.segment_efforts.count).to eq(3)
    end

    it "keeps a loop shared with another workout when one stops closing it" do
      user = create(:user)
      sport = create(:sport)
      first = import_three_laps(user, sport)
      described_class.perform_now(first)
      loop_segment = Segment.find_by!(source_workout: first, kind: "loop")

      second = import_three_recorded_laps(user, sport)
      described_class.perform_now(second)
      track_segment = second.track_segments.sole
      track_segment.update!(points: track_segment.points.first(2), points_count: 2)

      described_class.perform_now(second)

      expect(loop_segment.reload).to be_persisted
      expect(loop_segment.segment_efforts.where(workout: second)).to be_empty
      expect(loop_segment.segment_efforts.where(workout: first).count).to eq(3)
      expect(loop_segment.efforts_count).to eq(3)
    end

    it "reuses its own loop when the stored indexes no longer match" do
      user = create(:user)
      sport = create(:sport)
      workout = import_three_laps(user, sport)
      described_class.perform_now(workout)
      loop_segment = Segment.find_by!(source_workout: workout, kind: "loop")
      loop_segment.update_columns(source_start_index: 1, source_end_index: 2)

      described_class.perform_now(workout)

      expect(Segment.where(source_workout: workout, kind: "loop").pluck(:id)).to eq([ loop_segment.id ])
      expect(loop_segment.segment_efforts.count).to eq(3)
    end

    it "is idempotent and does not duplicate the loop" do
      user = create(:user)
      sport = create(:sport)
      workout = import_three_laps(user, sport)

      described_class.perform_now(workout)
      loop_id = Segment.find_by!(source_workout: workout, kind: "loop").id
      described_class.perform_now(workout)

      expect(Segment.where(source_workout: workout, kind: "loop").pluck(:id)).to eq([ loop_id ])
      expect(SegmentEffort.where(segment_id: loop_id).count).to eq(3)
    end

    it "persists no loop for a workout that does not close a circuit" do
      workout = create(:workout)
      create(:track_segment, workout:)

      described_class.perform_now(workout)

      expect(Segment.where(kind: "loop")).to be_empty
    end

    it "drops the candidate when fewer than two traversals complete" do
      user = create(:user)
      sport = create(:sport)
      workout = import_three_laps(user, sport)
      # Corrupt the geometry so only a single traversal can match: keep the
      # first loop, drop the rest.
      segment = workout.track_segments.sole
      segment.update!(points: segment.points.first(5), points_count: 5)

      described_class.perform_now(workout)

      expect(Segment.where(source_workout: workout, kind: "loop")).to be_empty
    end

    it "converges duplicate loops onto the owner-renamed one, not the oldest" do
      user = create(:user)
      sport = create(:sport)
      first = import_three_laps(user, sport)
      described_class.perform_now(first)
      keeper = Segment.find_by!(source_workout: first, kind: "loop")
      second = import_three_recorded_laps(user, sport)
      described_class.perform_now(second)
      # A legacy duplicate of the same circuit, renamed by the owner.
      renamed = create(:segment, :loop, user:, source_workout: second,
        name: "Tour du lac", renamed_at: Time.current,
        geom: keeper.geom, start_point: keeper.start_point, end_point: keeper.end_point,
        bounds: keeper.bounds, distance: keeper.distance)
      second.segment_efforts.update_all(segment_id: renamed.id)
      Segments::Refresh.call(renamed)

      described_class.perform_now(second)
      described_class.perform_now(first)

      expect(Segment.where(kind: "loop").pluck(:id)).to eq([ renamed.id ])
      expect(renamed.reload.name).to eq("Tour du lac")
      expect(renamed.efforts_count).to eq(6)
    end

    it "keeps an owner-renamed loop through the orphan sweep and drops an unnamed one" do
      user = create(:user)
      sport = create(:sport)
      workout = import_three_laps(user, sport)
      described_class.perform_now(workout)
      renamed = Segment.find_by!(source_workout: workout, kind: "loop")
      renamed.update!(name: "Tour du lac", renamed_at: Time.current)
      renamed.segment_efforts.delete_all
      # An unnamed loop far from the unrelated workout's track, so nothing
      # matches it and it stays a true orphan.
      far = RGeo::Geographic.spherical_factory(srid: 4326)
      bare = create(:segment, :loop, user:, name: "Morning ride loop",
        geom: far.line_string([ far.point(7.0, 45.0710), far.point(7.0018, 45.0728) ]),
        start_point: far.point(7.0, 45.0710), end_point: far.point(7.0018, 45.0728),
        bounds: [ 45.0710, 7.0, 45.0728, 7.0018 ])
      unrelated = create(:workout, user:, sport:)
      create(:track_segment, workout: unrelated)

      described_class.perform_now(unrelated)

      expect(Segment.exists?(renamed.id)).to be(true)
      expect(Segment.exists?(bare.id)).to be(false)
    end

    it "never deletes a loop renamed after the job read it, before the orphan sweep" do
      user = create(:user)
      sport = create(:sport)
      workout = import_three_laps(user, sport)
      described_class.perform_now(workout)
      renamed = Segment.find_by!(source_workout: workout, kind: "loop")
      renamed.segment_efforts.delete_all
      # The owner renames the loop after detection has read it, before the
      # orphan sweep deletes it.
      allow(Segments::LoopDetection).to receive(:new).and_wrap_original do |original, **kwargs|
        original.call(**kwargs).tap do
          Segments::Updater.new(segment: renamed, attributes: { "name" => "Tour du lac" }).call
        end
      end
      unrelated = create(:workout, user:, sport:)
      create(:track_segment, workout: unrelated)

      described_class.perform_now(unrelated)

      expect(Segment.exists?(renamed.id)).to be(true)
      expect(renamed.reload.name).to eq("Tour du lac")
    end
  end
end
