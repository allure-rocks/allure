# frozen_string_literal: true

require "rails_helper"

# A remote invitation as the invited account's instance receives it
# (docs/dev/SHARED-ACTIVITIES.md): addressed to one local account that holds the
# publication through an active entitlement, idempotent, never re-offered
# after a refusal.
RSpec.describe "Receiving a remote participation invitation" do
  let(:paul) { create(:user, username: "paul") }
  let!(:paul_actor) { create(:local_actor, user: paul) }
  let(:owner_actor) do
    create(:actor, uri: "https://remote.example/users/marie", inbox_url: "https://remote.example/inbox",
                   display_name: "Marie", handle: "marie", acct: "marie@remote.example")
  end
  let(:note) { create(:remote_note, actor: owner_actor, title: "Sortie du soir") }
  let!(:entitlement) { create(:remote_note_recipient, remote_note: note, recipient_actor: paul_actor) }
  let!(:follow) { create(:following, :accepted, follower_actor: paul_actor, followed_actor: owner_actor) }

  def invite_activity(id: "https://remote.example/users/marie/activities/invite-1", **overrides)
    {
      "id" => id, "type" => "Invite", "actor" => owner_actor.uri, "object" => note.object_uri,
      "target" => paul_actor.uri, "to" => [ paul_actor.uri ], "cc" => [],
      "_allure_participation" => { "sport_slug" => "hiking", "started_at" => "2026-08-26T12:00:00Z" }
    }.merge(overrides)
  end

  def inbound(activity)
    item = create(:federation_inbox_item, recipient_actor: paul_actor, activity_uri: activity.fetch("id"),
                                          activity_type: "Invite", actor_uri: activity.fetch("actor"), raw: activity)
    Federation::ProcessInboxItemJob.perform_now(item)
    item.reload
  end

  it "keeps the invitation and tells the invited account" do
    item = inbound(invite_activity)

    expect(item.status).to eq("processed")
    participation = RemoteParticipation.sole
    expect(participation).to have_attributes(
      remote_note: note, recipient_actor: paul_actor, object_uri: note.object_uri,
      invite_activity_uri: invite_activity.fetch("id"), sport_slug: "hiking"
    )
    expect(participation).to be_pending
    expect(participation.started_at).to eq(Time.utc(2026, 8, 26, 12))
    notice = Notification.find_by!(user: paul, kind: "participation_requested")
    expect(notice).to have_attributes(subject: participation, actor: owner_actor)
  end

  it "is idempotent, and keeps one live invitation per publication" do
    item = inbound(invite_activity)
    Federation::Inbox::ParticipationInvite.new(item:, activity: invite_activity).call!
    inbound(invite_activity(id: "https://remote.example/users/marie/activities/invite-2"))

    expect(RemoteParticipation.count).to eq(1)
  end

  it "lets a new Invite take over a pending invitation, so a late Undo of the old one misses it" do
    inbound(invite_activity)
    renewed = "https://remote.example/users/marie/activities/invite-2"
    inbound(invite_activity(id: renewed))

    expect(RemoteParticipation.sole.invite_activity_uri).to eq(renewed)
  end

  it "retries an Invite that overtook the publication from a followed author" do
    item = inbound(invite_activity("object" => "https://remote.example/api/v1/trail/not-yet"))

    expect(item.status).not_to eq("rejected")
    expect(item.last_error).to include("not arrived")
  end

  it "refuses an invitation from an author the account no longer follows" do
    follow.destroy!

    item = inbound(invite_activity)

    expect(item.status).to eq("rejected")
    expect(item.last_error).to include("does not follow the author")
    expect(RemoteParticipation.count).to eq(0)
    expect(Notification.where(user: paul, kind: "participation_requested")).not_to exist
  end

  it "never offers a refused publication again" do
    inbound(invite_activity)
    RemoteParticipation.sole.update!(declined_at: Time.current)

    inbound(invite_activity(id: "https://remote.example/users/marie/activities/invite-2"))

    expect(RemoteParticipation.count).to eq(1)
    expect(RemoteParticipation.sole).to be_declined
  end

  it "refuses an account without an active entitlement, even on a public note" do
    entitlement.update!(status: "withdrawn", withdrawn_at: Time.current, withdrawal_reason: "unfollow")

    item = inbound(invite_activity)

    expect(item.status).to eq("rejected")
    expect(RemoteParticipation.count).to eq(0)
  end

  it "refuses an invitation from anyone but the publication's author, or naming another account" do
    other = create(:actor, uri: "https://remote.example/users/eve")

    expect(inbound(invite_activity(id: "https://remote.example/a1", "actor" => other.uri)).status).to eq("rejected")
    expect(inbound(invite_activity(id: "https://remote.example/a2", "target" => "https://remote.example/users/x")).status)
      .to eq("rejected")
    # From a followed author an unknown publication may still be on its way.
    follow.destroy!
    expect(inbound(invite_activity(id: "https://remote.example/a3", "object" => "https://remote.example/unknown")).status)
      .to eq("rejected")
    expect(RemoteParticipation.count).to eq(0)
  end

  it "drops a malformed sport and start rather than trusting them" do
    inbound(invite_activity("_allure_participation" => { "sport_slug" => "<script>", "started_at" => "yesterday" }))

    expect(RemoteParticipation.sole).to have_attributes(sport_slug: nil, started_at: nil)
  end

  describe "the notice" do
    before { sign_in_as(paul) }

    it "names the owner and the received note, opens it, and survives a webhook endpoint", type: :request do
      paul.webhook_endpoints.create!(url: "https://hooks.example.com/allure", events: %w[participation.requested])
      inbound(invite_activity)
      event = WebhookEvent.find_by!(user: paul, event_type: "participation.requested")
      expect(event.payload).to include("remote_note_id" => Allure::ShortId.encode(note.uuid), "kind" => "credit")
      expect(event.payload).not_to have_key("workout_id")
      notice = Notification.find_by!(user: paul, kind: "participation_requested")

      get notifications_path
      expect(response.body).to include(ERB::Util.html_escape(
        I18n.t("notifications.kinds.participation_requested", name: "Marie", title: "Sortie du soir")
      ))

      get notification_path(notice)
      expect(response).to redirect_to(remote_note_path(note))
    end
  end
end
