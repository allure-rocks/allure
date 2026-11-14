# frozen_string_literal: true

require "rails_helper"
require "rake"

# The seed half of the demo instance's nightly reset (PLAN_DEMO.md §5): dates
# re-anchored on the present, one published password and random ones for
# every background persona, a quiet notification bell, and a session id
# sequence that never lets yesterday's signed cookie resume tomorrow's
# stranger.
RSpec.describe Demo::Reset do
  around do |example|
    previous = ENV.to_h.slice("DEMO_INSTANCE", "DEMO_DATASET", "DEMO_ACCOUNTS", "DEMO_PASSWORD",
                              "DEMO_OPERATOR_PASSWORD", "INSTANCE_OPERATOR_USERNAME")
    ENV.delete("DEMO_INSTANCE")
    ENV.delete("DEMO_DATASET")
    ENV.delete("DEMO_ACCOUNTS")
    ENV.delete("DEMO_PASSWORD")
    ENV.delete("DEMO_OPERATOR_PASSWORD")
    ENV.delete("INSTANCE_OPERATOR_USERNAME")
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  let(:fixture_start) do
    Allure::Gpx::Parser.new.parse(File.open(Rails.root.join("spec/fixtures/gpx/running_5k.gpx")))
      .segments.first.points.first.time
  end

  # A tiny manifest whose anchors match its own recordings' dates, so the
  # seeded rows land on the present whatever the fixture's fixed date is.
  # Marie's comments and reactions give Tom four distinct notifications.
  let(:manifest) do
    {
      accounts: [
        { username: "tom", email: "tom@demo.allure.rocks", locale: "en",
          workouts: [
            { key: :run, fixture: "gpx/running_5k.gpx", title: "Demo run", publish: :public },
            { key: :ride, fixture: "gpx/multi_segment.gpx", title: "Demo ride", sport: "cycling_road", publish: :public }
          ],
          manual_workouts: [ { key: :gym, sport: "fitness", title: "Salle", started_at: "2026-02-16T18:30", duration: 2700 } ] },
        { username: "marie", email: "marie@demo.allure.rocks", locale: "fr" }
      ],
      comments: [
        { author: "marie", owner: "tom", workout: :run, body: "Nice pace." },
        { author: "marie", owner: "tom", workout: :ride, body: "Strong finish." }
      ],
      reactions: [
        { by: "marie", owner: "tom", workout: :run, kind: "coffee" },
        { by: "marie", owner: "tom", workout: :ride, kind: "beer" }
      ]
    }
  end
  let(:anchors) { { files: fixture_start.to_date, manual: Date.new(2026, 2, 16) } }
  let(:out) { StringIO.new }
  let(:sequence) { -> { ActiveRecord::Base.connection.select_value("SELECT last_value FROM sessions_id_seq").to_i } }

  it "refuses to run outside demo mode" do
    expect { described_class.new(manifest:, anchors:, out:).call }
      .to raise_error(Demo::Reset::NotDemoInstance)
  end

  it "refuses a shared operator before assigning any credentials" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = "tom,marie"
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"

    expect { described_class.new(manifest:, anchors:, out:).call }
      .to raise_error(Allure::Demo::InvalidConfiguration)
    expect(User.count).to eq(0)
  end

  it "gives the configured operator a stable password and the published account the shared one" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = "tom"
    ENV["DEMO_PASSWORD"] = "AllureRocks2026"
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"
    ENV["DEMO_OPERATOR_PASSWORD"] = "operator-password-2026"

    reset = described_class.new(manifest:, anchors:, out:)
    summary = reset.call

    expect(summary.failed).to eq(0), out.string
    expect(User.find_by!(username: "tom").authenticate("AllureRocks2026")).to be_truthy
    expect(User.find_by!(username: "marie").authenticate("operator-password-2026")).to be_truthy
    expect(User.find_by!(username: "marie").authenticate(DemoSeed::PASSWORD)).to be_falsey

    # A re-run re-assigns the same configured password, never a random one.
    reset.call
    expect(User.find_by!(username: "marie").authenticate("operator-password-2026")).to be_truthy
  end

  it "refuses an operator password that is the shared one before seeding" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = "tom"
    ENV["DEMO_PASSWORD"] = "AllureRocks2026"
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"
    ENV["DEMO_OPERATOR_PASSWORD"] = "AllureRocks2026"

    expect { described_class.new(manifest:, anchors:, out:).call }
      .to raise_error(Allure::Demo::InvalidConfiguration, /must differ from DEMO_PASSWORD/)
    expect(User.count).to eq(0)
  end

  it "refuses the public development constant as the operator's password" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = "tom"
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"
    ENV["DEMO_OPERATOR_PASSWORD"] = DemoSeed::PASSWORD

    expect { described_class.new(manifest:, anchors:, out:).call }
      .to raise_error(Allure::Demo::InvalidConfiguration, /public development password/)
    expect(User.count).to eq(0)
  end

  it "seeds the social dataset with the deployment's federation settings, without remote deliveries" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = "tom"
    ENV["FEDERATION_ENABLED"] = "false"

    social_manifest = manifest.deep_dup
    social_manifest[:follows] = [ { from: "tom", to: "marie" } ]
    social_manifest[:accounts].first[:workouts].first[:publish] = [ :public, :followers ]
    social_manifest[:participations] = [ { owner: "tom", workout: :run, participant: "marie", decision: "confirm" } ]
    summary = nil
    expect {
      summary = described_class.new(manifest: social_manifest, anchors:, out:).call
    }.not_to have_enqueued_job(Federation::ExpandOutboxEventJob)

    expect(summary.failed).to eq(0), out.string
    expect(Following.accepted.count).to eq(1)
    expect(Following.accepted.sole.followed_actor.user.username).to eq("marie")
    expect(WorkoutPublication.active.where(audience: "followers").count).to eq(1)
    expect(WorkoutParticipation.confirmed.count).to eq(1)
    expect(FederationDelivery.count).to eq(0)
  end

  it "seeds with dates re-anchored on the present, no second factor, and the demo's passwords" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = "tom"
    ENV["DEMO_PASSWORD"] = "AllureRocks2026"

    summary = described_class.new(manifest:, anchors:, out:).call

    expect(summary.failed).to eq(0), out.string
    tom = User.find_by!(username: "tom")
    marie = User.find_by!(username: "marie")
    expect(tom.totp_enrolled?).to be(false)
    expect(marie.totp_enrolled?).to be(false)
    # The published account keeps the shared password; the background persona
    # gets an unknowable random one (PLAN_DEMO.md §3).
    expect(tom.authenticate("AllureRocks2026")).to be_truthy
    expect(tom.authenticate(DemoSeed::PASSWORD)).to be_falsey
    expect(marie.authenticate(DemoSeed::PASSWORD)).to be_falsey

    run = tom.workouts.find_by!(title: "Demo run")
    expect(run.time_shift_seconds).to be_positive
    expect(run.started_at).to be_between(2.days.ago, Time.current)
    gym = tom.workouts.manual_entries.find_by!(title: "Salle")
    expect(gym.started_at).to be_between(2.days.ago, Time.current)
  end

  it "leaves only the shared accounts' few newest notifications unread" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = "tom"

    summary = described_class.new(manifest:, anchors:, out:).call

    expect(summary.failed).to eq(0), out.string
    tom = User.find_by!(username: "tom")
    expect(tom.notifications.count).to eq(4)
    expect(Notification.where(read_at: nil).count).to eq(described_class::UNREAD_NOTIFICATIONS)
    # The unread ones are the newest.
    read = tom.notifications.where.not(read_at: nil).sole
    unread = tom.notifications.where(read_at: nil).order(:created_at)
    expect(read.created_at).to be < unread.first.created_at
  end

  it "randomizes the session id sequence on an empty table and leaves live sessions alone" do
    ENV["DEMO_INSTANCE"] = "true"
    reset = described_class.new(manifest:, anchors:, out:)

    reset.call
    expect(sequence.call).to be >= 10_000_000

    # A mid-day re-run with live sessions never rewinds the sequence onto
    # them: the randomization only happens while the table is empty.
    User.find_by!(username: "tom").sessions
      .create!(user_agent: "test", ip_address: nil, last_seen_at: Time.current, reauthenticated_at: Time.current)
    expect { reset.call }.not_to change { sequence.call }
  end
end

RSpec.describe "demo:reset task" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  it "exists and refuses outside demo mode" do
    expect(Rake::Task.task_defined?("demo:reset")).to be(true)

    expect { Rake::Task["demo:reset"].invoke }
      .to raise_error(SystemExit) { |exit| expect(exit.status).to be_nonzero }
      .and output(/DEMO_INSTANCE/).to_stderr
  end
end
