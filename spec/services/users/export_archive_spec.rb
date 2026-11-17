# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::ExportArchive do
  let(:now) { Time.utc(2026, 10, 18, 9) }
  let(:user) { create(:user, :with_totp, username: "rider_export", bio: "Grimpeur") }
  let(:gpx) { gpx_fixture_path("galibier").binread }
  let(:path) { Rails.root.join("tmp", "export-spec-#{SecureRandom.hex(4)}.zip").to_s }

  after { FileUtils.rm_f(path) }

  def recording(started_at)
    create(:workout, user:, started_at:).tap do |workout|
      workout.original_file.attach(io: StringIO.new(gpx), filename: "ride.gpx", content_type: "application/gpx+xml")
    end
  end

  def entries
    Zip::File.open(path) { |zip| zip.entries.to_h { [ it.name, it.get_input_stream.read ] } }
  end

  it "writes every part of the archive, with counts" do
    recording(Time.utc(2026, 8, 1, 6))
    user.sessions.create!(user_agent: "Firefox", ip_address: "192.0.2.10", last_seen_at: now, auth_method: "password")

    counts = described_class.new(user:, now:).write(path)

    expect(entries.keys).to include(
      "LISEZMOI.txt", "README.txt", "account.json", "sessions.json", "workouts/index.json", "workouts/index.csv",
      "workouts/originals-001.zip", "records.json", "segments.json", "segments.geojson", "equipment.json",
      "publishing_profiles.json", "privacy_zones.geojson", "publications.json", "social/following.csv",
      "social/followers.csv", "social/comments.json", "social/reactions.json"
    )
    expect(counts).to include("workouts" => 1, "originals" => 1)
    expect(JSON.parse(entries["account.json"])).to include("username" => "rider_export", "bio" => "Grimpeur",
                                                          "export_version" => 1)
    expect(JSON.parse(entries["sessions.json"]).sole).to include("ip_address" => "192.0.2.10", "device" => "Firefox")
  end

  it "exports the contribution history and preferences without provider payloads" do
    create(:funding_contribution, user:, metadata: { "private_provider_field" => "not exported" })
    user.update!(funding_badge_hidden: true, funding_badge_color: "teal")
    described_class.new(user:, now:).write(path)
    account = JSON.parse(entries["account.json"])
    expect(account.fetch("funding_contributions").sole).to include("provider" => "manual", "tier" => "coffee", "status" => "active")
    expect(account.fetch("preferences")).to include("funding_badge_hidden" => true, "funding_badge_color" => "teal")
    expect(entries["account.json"]).not_to include("private_provider_field", "not exported")
  end

  it "exports the two independent profile-sharing preferences" do
    user.update!(profile_statistics_audience: "members", profile_records_audience: "followers", discoverable: "members")

    described_class.new(user:, now:).write(path)

    expect(JSON.parse(entries["account.json"]).fetch("preferences")).to include(
      "profile_statistics_audience" => "members", "profile_records_audience" => "followers",
      "discoverable" => "members"
    )
  end

  it "exports paid periods and subscription state without customer or subscription identifiers" do
    subscription = create(:funding_subscription, user:, cancel_at_period_end: true)
    contribution = create(:funding_contribution, :subscription, funding_subscription: subscription)
    described_class.new(user:, now:).write(path)
    account = JSON.parse(entries["account.json"])
    expect(account.fetch("funding_contributions").sole).to include("starts_at" => contribution.starts_at.utc.iso8601)
    expect(account.fetch("funding_subscriptions").sole).to include("provider" => "stripe", "status" => "active", "cancel_at_period_end" => true)
    expect(entries["account.json"]).not_to include(subscription.customer_id, subscription.external_id)
  end

  it "exports photo originals byte for byte with captions and order, including failed photos" do
    workout = create(:workout, user:)
    body = photo_bytes
    photo = Workouts::PhotoUpload.new(user:, workout:).call(StringIO.new(body))
    photo.update!(status: "failed", caption: "A private view")
    other = create(:workout_photo)

    counts = described_class.new(user:, now:).write(path)

    expect(counts["photos"]).to eq(1)
    name = "photos/#{workout.to_param}/#{photo.to_param}.jpg"
    expect(entries[name].b).to eq(body)
    expect(JSON.parse(entries["photos/index.json"]).sole).to include("caption" => "A private view", "position" => 0, "file" => name)
    expect(entries.keys.join).not_to include(other.to_param)
  end

  it "lists each workout in JSON and CSV, pointing at its original" do
    workout = recording(Time.utc(2026, 8, 1, 6))

    described_class.new(user:, now:).write(path)

    json = JSON.parse(entries["workouts/index.json"]).sole
    expect(json).to include("id" => workout.to_param, "title" => "Morning ride", "distance" => 250.0)
    csv = CSV.parse(entries["workouts/index.csv"], headers: true).first
    expect(csv["id"]).to eq(workout.to_param)
    expect(csv["original_file"]).to eq("workouts/originals-001.zip!/2026-08-01_0600_#{workout.to_param}.gpx")
  end

  it "keeps the originals byte for byte, in archives the import page reads back" do
    recording(Time.utc(2026, 8, 1, 6))
    recording(Time.utc(2026, 8, 2, 6))
    recording(Time.utc(2026, 8, 3, 6))
    stub_const("#{described_class}::ORIGINALS_PER_ARCHIVE", 2)

    described_class.new(user:, now:).write(path)

    expect(entries.keys.grep(/originals/)).to eq(%w[workouts/originals-001.zip workouts/originals-002.zip])
    read_back = []
    entries.slice("workouts/originals-001.zip", "workouts/originals-002.zip").each do |name, bytes|
      Workouts::ArchiveReader.new.each_entry(StringIO.new(bytes), filename: File.basename(name)) do |entry|
        read_back << [ entry.name, entry.io.read ]
      end
    end
    expect(read_back.size).to eq(3)
    expect(read_back.map(&:last)).to all(eq(gpx))
  end

  it "never writes a secret" do
    _token, secret = ApiToken.issue!(user:, name: "Spec client", scopes: %w[read])
    codes = RecoveryCode.generate_for!(user)

    described_class.new(user:, now:).write(path)

    archive = entries.values.join("\n")
    expect(archive).not_to include(secret)
    expect(archive).not_to include(user.otp_secret)
    expect(archive).not_to include(user.password_digest)
    expect(codes).to be_present
    codes.each { expect(archive).not_to include(it) }
    expect(JSON.parse(entries["account.json"]).dig("second_factors", "authenticator_app_enrolled_at")).to be_present
  end

  it "exports the account's following and followers in Mastodon's address format" do
    actor = Federation::ActorProvisioner.new(user:).call!
    remote = create(:actor, acct: "marie@remote.example")
    create(:following, :accepted, follower_actor: actor, followed_actor: remote)

    described_class.new(user:, now:).write(path)

    expect(CSV.parse(entries["social/following.csv"])).to eq([
      [ "Account address", "Show boosts", "Notify on new posts", "Languages" ],
      [ "marie@remote.example", "true", "false", nil ]
    ])
  end

  it "writes federated text into the CSV files as text, never as a formula (docs/dev/ACCOUNT.md)" do
    actor = Federation::ActorProvisioner.new(user:).call!
    hyperlink = %(=HYPERLINK("http://evil.example","Open")@evil.example)
    create(:following, :accepted, follower_actor: create(:actor, acct: hyperlink), followed_actor: actor)
    create(:following, :accepted, follower_actor: actor, followed_actor: create(:actor, acct: "+cmd@evil.example"))
    recording(Time.utc(2026, 8, 1, 6)).update!(title: "=1+1")

    described_class.new(user:, now:).write(path)

    csv = CSV.parse(entries["workouts/index.csv"], headers: true).first
    expect(csv["title"]).to eq("'=1+1")
    expect(JSON.parse(entries["workouts/index.json"]).sole["title"]).to eq("=1+1")
    expect(CSV.parse(entries["social/followers.csv"]).last).to eq([ "'#{hyperlink}" ])
    expect(CSV.parse(entries["social/following.csv"]).last.first).to eq("'+cmd@evil.example")
  end
end
