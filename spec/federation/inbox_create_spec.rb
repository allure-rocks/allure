# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Inbox::Create do
  let(:recipient) { create(:local_actor) }
  let(:author) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      raw: { "followers" => "https://remote.example/users/demo/followers" }
    )
  end
  let(:activity) { federation_note_activity }
  let!(:follow) { create(:following, :accepted, follower_actor: recipient, followed_actor: author) }
  let(:item) do
    create(
      :federation_inbox_item,
      recipient_actor: recipient,
      activity_uri: activity.fetch("id"),
      activity_type: "Create",
      actor_uri: author.uri,
      raw: activity
    )
  end

  def process(activity: self.activity, item: self.item)
    described_class.new(item:, activity:).call!
  end

  it "persists one active note, one entitlement, and pending descriptors" do
    note = process

    expect(note).to be_active
    expect(note.public?).to be(true)
    expect(note.actor).to eq(author)
    expect(note.title).to eq("Morning hike")
    expect(note.metrics.fetch("distance")).to eq(23_064.640055)
    expect(note.source_domain).to eq("remote.example")
    expect(note).to be_entitled_to(recipient)
    expect(note.attachments.pending.pluck(:kind)).to eq([ "gpx" ])
    expect(note.representation.fetch("location")).to eq("longitude" => 6.4, "latitude" => 45.0)
  end

  it "stores record markers in the remote representation" do
    activity["object"]["tag"] << { "type" => "Note", "name" => "record_types", "content" => "FD,HA" }
    activity["object"]["tag"] << { "type" => "Note", "name" => "record_distances", "content" => "km5" }

    note = process

    expect(note.representation.fetch("record_types")).to eq(%w[FD HA])
    expect(note.representation.fetch("record_distances")).to eq(%w[km5])
  end

  it "stores the shared recording device in the remote representation" do
    activity["object"]["tag"] << { "type" => "Note", "name" => "device", "content" => "Garmin Edge 530" }

    note = process

    expect(note.representation.fetch("device")).to eq("Garmin Edge 530")
  end

  it "stores the commute flag in the remote representation" do
    activity["object"]["tag"] << { "type" => "Note", "name" => "commute", "content" => "true" }

    note = process

    expect(note.representation.fetch("commute")).to be(true)
  end

  it "stores a shared weather summary and drops an implausible one (PLAN_WEATHER.md §6)" do
    activity["object"]["tag"].push(
      { "type" => "Note", "name" => "weather_condition", "content" => "rain" },
      { "type" => "Note", "name" => "weather_temperature", "content" => "9.5,13.2,7.0" },
      { "type" => "Note", "name" => "weather_wind", "content" => "4.1,9.8,225" },
      { "type" => "Note", "name" => "weather_wind_exposure", "content" => "0.420,0.310,0.270,0.80" }
    )

    weather = process.representation.fetch("weather")

    expect(weather).to include("condition" => "rain", "temperature_min" => 9.5, "wind_direction" => 225.0)
    expect(weather["wind_exposure"]).to include("head" => 0.42, "headwind" => 0.8)
  end

  it "drops an implausible weather summary" do
    activity["object"]["tag"] << { "type" => "Note", "name" => "weather_temperature", "content" => "90,120," }

    expect(process.representation).not_to have_key("weather")
  end

  it "stores comments closed by the origin in the remote representation" do
    activity["object"]["tag"] << { "type" => "Note", "name" => "comments", "content" => "closed" }

    note = process

    expect(note.representation.fetch("comments_closed")).to be(true)
    expect(Federation::RemoteNoteView.new(note).comments_closed?).to be(true)
  end

  it "is idempotent for a duplicate delivery to the same recipient" do
    first = process
    second = process

    expect(second).to eq(first)
    expect(RemoteNote.count).to eq(1)
    expect(RemoteNoteRecipient.count).to eq(1)
    expect(RemoteNoteAttachment.count).to eq(1)
  end

  it "adds a separate entitlement for another local recipient" do
    note = process
    other = create(:local_actor)
    create(:following, :accepted, follower_actor: other, followed_actor: author)
    other_item = create(
      :federation_inbox_item,
      recipient_actor: other,
      activity_uri: activity.fetch("id"),
      activity_type: "Create",
      actor_uri: author.uri,
      raw: activity
    )

    second = process(item: other_item)

    expect(second).to eq(note)
    expect(RemoteNoteRecipient.where(remote_note: note).count).to eq(2)
    expect(note.entitled_to?(other)).to be(true)
  end

  it "never reactivates a withdrawn entitlement on a duplicate delivery" do
    note = process
    recipient_record = note.recipients.find_by!(recipient_actor: recipient)
    recipient_record.withdraw!(reason: "unfollow")

    process

    expect(recipient_record.reload).to be_withdrawn
    expect(note.entitled_to?(recipient)).to be(false)
  end

  # docs/dev/FEDERATION.md: naming a local account is not enough to reach it.
  it "rejects a note addressed directly to an account that does not follow its author" do
    follow.destroy!
    direct = [ Federation::Parsers::RemoteNote::PUBLIC_AUDIENCE, recipient.uri ]
    activity["to"] = direct
    activity["object"]["to"] = direct

    expect { process }.to raise_error(Federation::Inbox::Rejected, /does not follow the author/)
    expect(RemoteNote.count).to eq(0)
    expect(RemoteNoteAttachment.count).to eq(0)
    expect(Federation::FollowingFeed.new(actor: recipient).relation.to_a).to be_empty
  end

  it "rejects a note for a pending follow" do
    follow.update!(status: "pending", accepted_at: nil)

    expect { process }.to raise_error(Federation::Inbox::Rejected, /does not follow the author/)
  end

  it "grants no entitlement to a non-follower when the note already reached a follower" do
    note = process
    stranger = create(:local_actor)
    stranger_item = create(
      :federation_inbox_item, recipient_actor: stranger, activity_uri: activity.fetch("id"),
                              activity_type: "Create", actor_uri: author.uri, raw: activity
    )

    expect { process(item: stranger_item) }.to raise_error(Federation::Inbox::Rejected)
    expect(note.entitled_to?(stranger)).to be(false)
    expect(note.entitled_to?(recipient)).to be(true)
  end

  it "rejects a Create for a tombstoned object" do
    create(:remote_note, :deleted, actor: author, object_uri: activity.dig("object", "id"))

    expect { process }.to raise_error(Federation::Inbox::Rejected, /already deleted/)
    expect(RemoteNote.active.count).to eq(0)
  end

  it "rejects followers-only audiences while the restricted gate is off" do
    followers_only = federation_note_activity
    followers_only["object"]["to"] = [ "https://remote.example/users/demo/followers" ]
    followers_only["object"]["cc"] = []
    followers_only["to"] = followers_only["object"]["to"]
    followers_only["cc"] = []

    expect { process(activity: followers_only) }
      .to raise_error(Federation::Inbox::Rejected, /restricted audience/)
  end

  it "persists a followers note while restricted federation is on" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    followers_only = federation_note_activity
    followers_only["object"]["to"] = [ "https://remote.example/users/demo/followers" ]
    followers_only["object"]["cc"] = []
    followers_only["to"] = followers_only["object"]["to"]
    followers_only["cc"] = []

    note = process(activity: followers_only)

    expect(note.audience).to eq("followers")
    expect(note).to be_entitled_to(recipient)
  end

  it "rejects a malformed object" do
    broken = federation_note_activity
    broken["object"]["attributedTo"] = "https://remote.example/users/other"

    expect { process(activity: broken) }
      .to raise_error(Federation::Inbox::Rejected, /attribution/)
  end

  it "rejects a blocked author" do
    create(:federation_actor_block, actor_uri: author.uri)

    expect { process }.to raise_error(Federation::Inbox::Rejected, /blocked/)
  end

  it "rejects a tombstoned author" do
    author.tombstone!

    expect { process }.to raise_error(Federation::Inbox::Rejected, /not available/)
  end

  it "rejects an activity whose sender does not match the item" do
    other = create(:federation_inbox_item, recipient_actor: recipient, actor_uri: "https://other.example/users/x")

    expect { process(item: other) }
      .to raise_error(Federation::Inbox::Rejected, /does not match the sender/)
  end
end
