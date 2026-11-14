# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/demo/seeder")

# The demo seeder drives the same services as the web UI. This manifest keeps
# every kind of step on committed GPX fixtures, so the loader cannot rot
# silently when a service changes; the development manifests only add data.
RSpec.describe DemoSeed::Runner do
  let(:manifest) do
    {
      accounts: [
        {
          username: "marie", email: "marie@allure.test", display_name: "Marie Dufour", locale: "fr", theme: "dark",
          time_zone: "Europe/Paris", default_sports: { cycling: "cycling_road" },
          equipment: [ { label: "Lapierre", type: "bike" }, { label: "Hoka", type: "shoes" } ],
          privacy_zones: [ { name: "Maison", latitude: 45.0, longitude: 6.4, radius_meters: 150 } ],
          built_in_profiles: { public: { settings: { "gpx" => true }, auto_publish: true, auto_publish_exclude_commute: true } },
          profiles: [ { name: "Sans itinéraire", settings: { "route" => false, "route_image" => false } } ],
          workouts: [
            { key: :run, fixture: "gpx/running_5k.gpx", title: "Cinq kilomètres", description: "Le long de la vallée.",
              notes: "Jambes lourdes.", equipment: [ "Hoka" ], publish: :public },
            { key: :ride, fixture: "gpx/galibier.gpx", title: "Galibier", sport: "cycling_road", equipment: [ "Lapierre" ], commute: true,
              publish: [ { audience: :public, delay: "1_day" }, :followers ] },
            { key: :laps, fixture: "gpx/three_laps_recorded.gpx", title: "Tours de piste", sport: "running", publish: { profile: "Sans itinéraire" } },
            { key: :missing, file: "Activity/2030/Activity_20300101_001_000_Running_Nowhere_00000000000000000000000000000000.fit", title: "Absent" }
          ],
          manual_workouts: [
            { key: :gym, sport: "fitness", title: "Salle", started_at: "2026-02-16T18:30", duration: 2700, calories: 290 },
            { key: :jog, sport: "running", title: "Sans montre", started_at: "2026-02-18T07:00", duration: 1800, moving_time: 1750,
              distance: 5_000, equipment: [ "Hoka" ] }
          ],
          batches: [
            { sport: "running", files: [ { key: :short, fixture: "gpx/running_type.gpx" }, { fixture: "gpx/malformed.gpx", as: "broken.gpx" } ] }
          ],
          segments: [
            { key: :climb, workout: :run, name: "Montée de la vallée", visibility: "public", publish: true, tolerance: 40,
              start: [ 45.0045, 6.4 ], end: [ 45.0404, 6.4 ] },
            { key: :laps_route, workout: :laps, name: "Tour de piste", kind: "route" }
          ]
        },
        {
          username: "paul", email: "paul@allure.test", locale: "en", unit_system: "imperial", time_zone: "America/Los_Angeles",
          workouts: [
            { key: :run, fixture: "gpx/running_5k.gpx", title: "Five kilometres", publish: :public },
            { key: :multi, fixture: "gpx/multi_segment.gpx", title: "Two segments", sport: "mountain_biking" }
          ]
        },
        { username: "nina", email: "nina@allure.test", locale: "fr", second_factor: false },
        { username: "spam", email: "spam@allure.test", locale: "en" }
      ],
      follows: [
        { from: "marie", to: "paul" }, { from: "paul", to: "marie" },
        { from: "nina", to: "marie", decision: "pending" }, { from: "paul", to: "nina", decision: "reject" }
      ],
      participations: [
        { owner: "marie", workout: :run, participant: "paul", decision: "confirm", with_workout: :run },
        { owner: "marie", workout: :ride, participant: "paul", decision: "confirm" },
        { owner: "marie", workout: :laps, participant: "paul", decision: "decline" }
      ],
      comments: [
        { key: :first, author: "paul", owner: "marie", workout: :run, body: "Nice pace." },
        { author: "marie", owner: "marie", workout: :run, parent: :first, body: "Merci !" },
        { author: "paul", owner: "marie", workout: :run, body: "Wrong activity.", state: :deleted },
        { author: "nina", owner: "marie", workout: :run, body: "Buy now!", state: :removed }
      ],
      closed_threads: [ { owner: "marie", workout: :laps } ],
      reactions: [ { by: "paul", owner: "marie", workout: :run, kind: "beer" }, { by: "nina", owner: "marie", workout: :run, kind: "like" } ],
      opt_outs: [ { user: "paul", owner: "marie", segment: :climb } ],
      copies: [ { user: "paul", owner: "marie", segment: :climb, reversed: true } ],
      api: [
        {
          user: "marie",
          tokens: [ { name: "Scripts", scopes: %w[read write], mcp_geometry: "filtered" }, { name: "Old", scopes: [ "read" ], revoked: true } ],
          webhooks: [ { url: "https://example.com/hooks", description: "Paused", active: false } ]
        }
      ],
      admin: {
        operator: "marie",
        invitations: [ "invite@allure.test" ],
        suspended: [ { username: "spam", reason: "Spam" } ],
        identities: [ { username: "nina", provider: "oidc", issuer: "https://issuer.example", subject: "subject-1" } ]
      }
    }
  end
  let(:out) { StringIO.new }

  def run
    described_class.new(
      manifest:,
      corpus_root: Rails.root.join("tmp/no-corpus"),
      fixtures_root: Rails.root.join("spec/fixtures"),
      out:
    ).call
  end

  def snapshot
    [ User, Equipment, PrivacyZone, PublishingProfile, Workout, WorkoutImportBatch, Segment, SegmentPublication,
      Following, WorkoutPublication, WorkoutParticipation, Comment, Reaction, SegmentOptOut, ApiToken, WebhookEndpoint,
      RegistrationInvitation, AdminEvent, Identity, Notification ].to_h { |model| [ model.name, model.count ] }
  end

  it "builds the whole dataset through the application services, then changes nothing on a second run" do
    summary = run

    expect(summary.failed).to eq(0), out.string
    expect(summary.imported).to eq(6)
    expect(out.string).to include("skipping Absent: no source file")

    marie = User.find_by!(username: "marie")
    paul = User.find_by!(username: "paul")
    nina = User.find_by!(username: "nina")
    expect(marie.authenticate(DemoSeed::PASSWORD)).to be_truthy
    expect(marie.totp_enrolled?).to be(true)
    expect(nina.totp_enrolled?).to be(false)
    expect(marie.default_cycling_sport.slug).to eq("cycling_road")
    expect(paul.unit_system).to eq("imperial")
    expect(marie.equipments.pluck(:label)).to contain_exactly("Lapierre", "Hoka")
    expect(marie.privacy_zones.pluck(:name)).to eq([ "Maison" ])

    public_profile = marie.publishing_profiles.find_by!(built_in_key: "public")
    expect(public_profile.settings).to include("gpx" => true, "mask_start" => false, "mask_finish" => false)
    expect(public_profile.auto_publish?).to be(true)
    custom = marie.publishing_profiles.find_by!(name: "Sans itinéraire")
    expect(custom.settings).to include("route" => false, "mask_start" => false)

    run_workout = marie.workouts.find_by!(title: "Cinq kilomètres")
    expect(run_workout.notes).to eq("Jambes lourdes.")
    expect(run_workout.equipments.pluck(:label)).to eq([ "Hoka" ])
    expect(marie.workouts.find_by!(title: "Galibier")).to be_commute
    batch = marie.workout_import_batches.sole
    expect(batch).to have_attributes(status: "completed", imported_entries: 1, failed_entries: 1)
    expect(marie.workouts.recordings.count).to eq(4)
    gym = marie.workouts.manual_entries.find_by!(title: "Salle")
    expect(gym).to have_attributes(duration: 2700, moving_time: 2700, calories: 290, started_at: Time.utc(2026, 2, 16, 17, 30))
    jog = marie.workouts.manual_entries.find_by!(title: "Sans montre")
    expect(jog).to have_attributes(distance: 5_000, pause_time: 50)
    expect(jog.equipments.pluck(:label)).to eq([ "Hoka" ])

    climb = marie.segments.find_by!(name: "Montée de la vallée")
    expect(climb).to have_attributes(kind: "segment", visibility: "public", source_workout: run_workout, match_tolerance_meters: 40)
    expect(climb.distance).to be_between(3_500, 4_500)
    expect(climb.active_publication).to be_present
    expect(marie.segments.find_by!(name: "Tour de piste")).to have_attributes(
      kind: "route", visibility: "private",
      match_tolerance_meters: Segments::Creator::ROUTE_MATCH_TOLERANCE_METERS
    )
    expect(paul.segments.find_by!(name: "Montée de la vallée (reversed)")).to have_attributes(visibility: "private")
    expect(SegmentOptOut.exists?(segment: climb, user: paul)).to be(true)

    expect(Following.accepted_between(follower_actor: marie.actor, followed_actor: paul.actor)).to exist
    expect(Following.find_by(follower_actor: nina.actor, followed_actor: marie.actor)).to be_pending
    expect(Following.find_by(follower_actor: paul.actor, followed_actor: nina.actor)).to be_rejected

    expect(run_workout.active_publications.map(&:audience)).to eq([ "public" ])
    # Every publication is dated a little after its workout (and its delay),
    # not at the seed run's instant.
    WorkoutPublication.active.includes(:workout).find_each do |publication|
      finished_at = publication.workout.started_at + publication.workout.duration
      expect(publication.published_at).to be_between(finished_at, finished_at + 2.days)
    end
    # Its day-long delay ran out long ago: it went live when the delay ended.
    ride = marie.workouts.find_by!(title: "Galibier")
    expect(ride.scheduled_publications).to be_empty
    # The followers audience is always publishable (PLAN_M5 §13.1).
    expect(ride.active_publications.map(&:audience)).to contain_exactly("public", "followers")
    ride_publication = ride.active_publications.find_by!(audience: "public")
    expect(ride_publication.published_at).to be > ride.started_at + ride.duration + 1.day
    expect(ride_publication.published_at).to be < Time.current
    laps = marie.workouts.find_by!(title: "Tours de piste")
    expect(laps.active_publications.sole.publishing_profile).to eq(custom)
    expect(laps.comments_closed_at).to be_present

    participations = marie.workouts.flat_map(&:workout_participations)
    expect(participations.map(&:kind)).to contain_exactly("link", "credit", "credit")
    expect(participations.find { |participation| participation.kind == "link" }.participant_workout).to eq(paul.workouts.find_by!(title: "Five kilometres"))
    expect(participations.count { |participation| participation.declined_at.present? }).to eq(1)

    expect(run_workout.comments.group(:status).count).to eq("active" => 2, "deleted" => 1, "removed" => 1)
    expect(run_workout.comments.active.map(&:parent_id).compact.length).to eq(1)
    expect(Reaction.active.where(workout: run_workout).pluck(:kind)).to contain_exactly("beer", "like")

    expect(ApiToken.authenticate(DemoSeed::API_TOKEN_SECRET)&.user).to eq(marie)
    expect(marie.api_tokens.find_by!(name: "Old")).to be_revoked
    expect(marie.webhook_endpoints.sole).to have_attributes(state: "paused", all_events?: true)

    expect(RegistrationInvitation.exists?(email_address: "invite@allure.test")).to be(true)
    expect(User.find_by!(username: "spam")).to be_suspended
    expect(AdminEvent.pluck(:action)).to contain_exactly("invitation_created", "account_suspended")
    expect(nina.identities.sole).to have_attributes(provider: "oidc", subject: "subject-1")

    before = snapshot
    second = run

    expect(second.failed).to eq(0), out.string
    expect(second.imported).to eq(0)
    expect(snapshot).to eq(before)
  end

  # On a demo the worker runs Together detection while the seed imports: a
  # suggestion may claim the participant's recording before the manifest links
  # it. The link must win whatever the timing, on the first run and after.
  it "links the participant's recording even when detection suggested it elsewhere first" do
    described_class.new(manifest: manifest.merge(participations: []), corpus_root: Rails.root.join("tmp/no-corpus"),
                        fixtures_root: Rails.root.join("spec/fixtures"), out:).call
    marie = User.find_by!(username: "marie")
    paul = User.find_by!(username: "paul")
    paul_run = paul.workouts.find_by!(title: "Five kilometres")
    detected = marie.workouts.find_by!(title: "Tours de piste").workout_participations.create!(
      participant_actor: paul.actor, participant_workout: paul_run, kind: "link", origin: "detection"
    )

    summary = run

    expect(summary.failed).to eq(0), out.string
    expect(detected.reload.withdrawn_at).to be_present
    link = marie.workouts.find_by!(title: "Cinq kilomètres").workout_participations.sole
    expect(link).to have_attributes(kind: "link", participant_workout: paul_run)
    expect(link.participant_confirmed_at).to be_present
  end

  it "re-dates every recording and skips second factors when the demo asks for it (PLAN_DEMO.md §4)" do
    shift = 86_400 * 10
    summary = described_class.new(
      manifest:,
      corpus_root: Rails.root.join("tmp/no-corpus"),
      fixtures_root: Rails.root.join("spec/fixtures"),
      out:,
      file_time_shift: shift,
      manual_time_shift: shift,
      enrol_second_factor: false
    ).call

    expect(summary.failed).to eq(0), out.string
    marie = User.find_by!(username: "marie")
    expect(marie.totp_enrolled?).to be(false)

    unshifted = Allure::Gpx::Parser.new.parse(File.open(Rails.root.join("spec/fixtures/gpx/running_5k.gpx")))
      .segments.first.points.first.time
    run_workout = marie.workouts.find_by!(title: "Cinq kilomètres")
    expect(run_workout.time_shift_seconds).to eq(shift)
    expect(run_workout.started_at).to eq(unshifted + shift)
    # The batch entry carries the same offset as every other recording.
    expect(marie.workouts.recordings.pluck(:time_shift_seconds).uniq).to eq([ shift ])
    # Manual entries shift on their own family's offset.
    gym = marie.workouts.manual_entries.find_by!(title: "Salle")
    expect(gym.started_at).to eq(Time.utc(2026, 2, 16, 17, 30) + shift)
  end

  it "holds a recent delayed publication until its delay ends after the workout" do
    recent = {
      accounts: [
        { username: "marie", email: "marie@allure.test", locale: "fr",
          workouts: [
            { key: :run, fixture: "gpx/running_5k.gpx", title: "Cinq kilomètres", publish: :public },
            { key: :ride, fixture: "gpx/galibier.gpx", title: "Galibier", sport: "cycling_road",
              publish: { audience: :public, delay: "1_week" } }
          ] }
      ]
    }
    # Both fixtures were recorded on 2026-06-01: the shift lands them yesterday.
    dating = DemoSeed::Dating.new(anchors: { files: Date.new(2026, 6, 1), manual: Date.new(2026, 6, 1) }, end_date: Date.current - 1)
    runner = lambda do
      described_class.new(manifest: recent, corpus_root: Rails.root.join("tmp/no-corpus"), fixtures_root: Rails.root.join("spec/fixtures"),
                          out:, file_time_shift: dating.file_shift, manual_time_shift: dating.manual_shift).call
    end

    summary = nil
    expect { summary = runner.call }.to have_enqueued_job(Workouts::ActivateScheduledPublicationJob).at_least(:once)

    expect(summary.failed).to eq(0), out.string
    marie = User.find_by!(username: "marie")
    run_workout = marie.workouts.find_by!(title: "Cinq kilomètres")
    run_publication = run_workout.active_publications.sole
    expect(run_publication.published_at).to be > run_workout.started_at + run_workout.duration
    expect(run_publication.published_at).to be <= Time.current

    ride = marie.workouts.find_by!(title: "Galibier")
    scheduled = ride.scheduled_publications.sole
    finished_at = ride.started_at + ride.duration
    expect(scheduled.scheduled_for).to be > Time.current
    expect(scheduled.scheduled_for).to be_between(finished_at + 1.week, finished_at + 1.week + 1.day)
    expect(scheduled.published_at).to eq(scheduled.scheduled_for)

    expect { runner.call }.not_to change { WorkoutPublication.pluck(:id, :status, :published_at, :scheduled_for).sort }
  end

  describe DemoSeed::Dating do
    let(:anchors) { { files: Date.new(2026, 4, 19), manual: Date.new(2026, 10, 13) } }

    it "ends each family yesterday on a database without the dataset" do
      dating = described_class.near_present(anchors:, usernames: [ "marie" ], today: Date.new(2026, 11, 3))

      expect(dating.file_shift).to eq((Date.new(2026, 11, 2) - anchors[:files]).to_i * 86_400)
      expect(dating.manual_shift).to eq((Date.new(2026, 11, 2) - anchors[:manual]).to_i * 86_400)
    end

    it "keeps the end date the dataset was first seeded with" do
      marie = create(:user, username: "marie")
      create(:workout, user: marie, time_shift_seconds: 10 * 86_400)

      dating = described_class.near_present(anchors:, usernames: [ "marie" ], today: Date.new(2026, 12, 25))

      expect(dating.file_shift).to eq(10 * 86_400)
      # The manual anchor lies after that end date: nothing moves forward.
      expect(dating.manual_shift).to eq(0)
    end

    it "shifts nothing when asked for the files' own dates" do
      expect([ described_class.none.file_shift, described_class.none.manual_shift ]).to eq([ 0, 0 ])
    end
  end

  it "assigns the passwords the demo's callable names, overwriting what exists (PLAN_DEMO.md §3)" do
    run
    described_class.new(
      manifest:,
      corpus_root: Rails.root.join("tmp/no-corpus"),
      fixtures_root: Rails.root.join("spec/fixtures"),
      out:,
      password_for: ->(username) { username == "paul" ? "AllureRocks2026" : "a-random-password-123" }
    ).call

    paul = User.find_by!(username: "paul")
    marie = User.find_by!(username: "marie")
    # The published account keeps the callable's password, not the repository's
    # development constant.
    expect(paul.authenticate("AllureRocks2026")).to be_truthy
    expect(paul.authenticate(DemoSeed::PASSWORD)).to be_falsey
    # Every other account's password is overwritten with an unknowable one.
    expect(marie.authenticate(DemoSeed::PASSWORD)).to be_falsey
    expect(marie.authenticate("a-random-password-123")).to be_truthy
  end
end
