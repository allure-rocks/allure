# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Safety::Blocking do
  let(:remote) { create(:actor, uri: "https://blocked.example/users/demo") }
  let(:other_remote) { create(:actor, uri: "https://other.example/users/demo") }
  let(:recipient) { create(:local_actor) }
  let(:note) { create(:remote_note, actor: remote, source_domain: "blocked.example") }
  let!(:entitlement) { create(:remote_note_recipient, remote_note: note, recipient_actor: recipient) }
  let!(:attachment) { create(:remote_note_attachment, remote_note: note, status: "cached") }

  describe "relationships with the blocked accounts" do
    let!(:following) { create(:following, :accepted, follower_actor: recipient, followed_actor: remote) }
    let!(:follower) do
      create(:following, follower_actor: remote, followed_actor: recipient,
                         uri: "https://blocked.example/activities/follow-1")
    end
    let!(:unrelated) { create(:following, :accepted, follower_actor: recipient, followed_actor: other_remote) }

    it "ends them in both directions when the domain is blocked, without telling anyone" do
      described_class.new.block_domain!(domain: "blocked.example")

      expect([ following.reload, follower.reload ]).to all(be_undone)
      expect(unrelated.reload).to be_accepted
      expect(FederationOutboxEvent.count).to eq(0)
    end

    it "ends them when the actor is blocked" do
      described_class.new.block_actor!(actor_uri: remote.uri)

      expect([ following.reload, follower.reload ]).to all(be_undone)
      expect(unrelated.reload).to be_accepted
    end
  end

  it "cancels what was still waiting to reach a blocked domain" do
    event = create(:federation_outbox_event, actor: recipient, subject_id: recipient.id, object_uri: recipient.uri,
                                             status: "expanded")
    waiting = create(:federation_delivery, outbox_event: event, inbox_url: "https://blocked.example/inbox",
                                           status: "retrying")
    elsewhere = create(:federation_delivery, outbox_event: event, inbox_url: "https://other.example/inbox",
                                             status: "retrying")

    described_class.new.block_domain!(domain: "blocked.example")

    expect(waiting.reload).to be_cancelled
    expect(elsewhere.reload).to be_retrying
  end

  describe "blocking a domain" do
    it "creates the block and withdraws the authority's entitlements" do
      block = described_class.new.block_domain!(domain: "blocked.example")

      expect(block).to be_persisted
      expect(entitlement.reload).to be_withdrawn
      expect(entitlement.withdrawal_reason).to eq("blocked")
    end

    it "retains public cached media" do
      described_class.new.block_domain!(domain: "blocked.example")

      expect(attachment.reload).to be_cached
    end

    it "purges a followers-only note's media when it is the last entitlement" do
      followers_note = create(
        :remote_note, actor: remote, source_domain: "blocked.example", audience: "followers"
      )
      followers_attachment = create(:remote_note_attachment, remote_note: followers_note, status: "cached")
      create(:remote_note_recipient, remote_note: followers_note, recipient_actor: recipient)

      described_class.new.block_domain!(domain: "blocked.example")

      expect(followers_attachment.reload).to be_purged
      expect(followers_note.reload).to be_location_data_purged
    end

    it "withdraws and purges an entitled remote course" do
      segment = create(:remote_segment, actor: remote, source_domain: "blocked.example", audience: "followers")
      segment_attachment = create(:remote_segment_attachment, remote_segment: segment, status: "cached")
      segment_recipient = create(:remote_segment_recipient, remote_segment: segment, recipient_actor: recipient)

      described_class.new.block_domain!(domain: "blocked.example")

      expect(segment_recipient.reload).to be_withdrawn
      expect(segment_recipient.withdrawal_reason).to eq("blocked")
      expect(segment_attachment.reload).to be_purged
      expect(segment.reload).to be_location_data_purged
    end

    it "withdraws entitlements from a case-variant actor URI" do
      upper = create(:actor, uri: "https://BLOCKED.example/users/demo")
      upper_note = create(:remote_note, actor: upper, source_domain: "blocked.example")
      upper_entitlement = create(:remote_note_recipient, remote_note: upper_note, recipient_actor: recipient)

      described_class.new.block_domain!(domain: "Blocked.Example")

      expect(upper_entitlement.reload).to be_withdrawn
      expect(upper_entitlement.withdrawal_reason).to eq("blocked")
    end

    it "reaches the domain's subdomains and other ports" do
      sub = create(:actor, uri: "https://x.blocked.example/users/demo")
      ported = create(:actor, uri: "https://blocked.example:8443/users/demo")
      notes = [ sub, ported ].map { |actor| create(:remote_note, actor:, source_domain: Allure::Federation::Authority.domain(actor.uri)) }
      entitlements = notes.map { |remote_note| create(:remote_note_recipient, remote_note:, recipient_actor: recipient) }
      follows = [ sub, ported ].map { |actor| create(:following, :accepted, follower_actor: recipient, followed_actor: actor) }
      event = create(:federation_outbox_event, actor: recipient, subject_id: recipient.id, object_uri: recipient.uri,
                                               status: "expanded")
      waiting = create(:federation_delivery, outbox_event: event, inbox_url: "https://x.blocked.example/inbox",
                                             status: "retrying")

      described_class.new.block_domain!(domain: "blocked.example")

      expect(entitlements.map { it.reload.withdrawal_reason }).to all(eq("blocked"))
      expect(follows.map { it.reload.status }).to all(eq("undone"))
      expect(waiting.reload).to be_cancelled
    end

    it "keeps a block with a port to that authority" do
      ported = create(:actor, uri: "https://blocked.example:8443/users/demo")
      ported_note = create(:remote_note, actor: ported, source_domain: "blocked.example:8443")
      ported_entitlement = create(:remote_note_recipient, remote_note: ported_note, recipient_actor: recipient)

      described_class.new.block_domain!(domain: "blocked.example:8443")

      expect(ported_entitlement.reload.withdrawal_reason).to eq("blocked")
      expect(entitlement.reload).to be_active
    end

    it "leaves other authorities untouched" do
      other_note = create(:remote_note, actor: other_remote, source_domain: "other.example")
      other_entitlement = create(:remote_note_recipient, remote_note: other_note, recipient_actor: recipient)

      described_class.new.block_domain!(domain: "blocked.example")

      expect(other_entitlement.reload).to be_active
    end

    it "withdraws the authority's notifications" do
      notification = create(:notification, user: recipient.user, actor: remote)

      described_class.new.block_domain!(domain: "blocked.example")

      expect(Notification.where(id: notification.id)).not_to exist
    end

    it "does not restore entitlements on unblock" do
      described_class.new.block_domain!(domain: "blocked.example")

      described_class.new.unblock_domain!(domain: "blocked.example")

      expect(FederationDomainBlock.where(domain: "blocked.example")).to be_empty
      expect(entitlement.reload).to be_withdrawn
    end
  end

  describe "blocking an actor" do
    it "creates the block and withdraws exactly that actor's entitlements" do
      other_note = create(:remote_note, actor: other_remote, source_domain: "other.example")
      other_entitlement = create(:remote_note_recipient, remote_note: other_note, recipient_actor: recipient)

      block = described_class.new.block_actor!(actor_uri: remote.uri)

      expect(block).to be_persisted
      expect(entitlement.reload).to be_withdrawn
      expect(other_entitlement.reload).to be_active
    end

    it "withdraws a case-variant actor's entitlements when the canonical URI is blocked" do
      upper = create(:actor, uri: "https://BLOCKED.example/users/demo")
      upper_note = create(:remote_note, actor: upper, source_domain: "blocked.example")
      upper_entitlement = create(:remote_note_recipient, remote_note: upper_note, recipient_actor: recipient)

      described_class.new.block_actor!(actor_uri: "https://blocked.example/users/demo")

      expect(upper_entitlement.reload).to be_withdrawn
    end

    it "does not restore entitlements on unblock" do
      described_class.new.block_actor!(actor_uri: remote.uri)

      described_class.new.unblock_actor!(actor_uri: remote.uri)

      expect(FederationActorBlock.where(actor_uri: remote.uri)).to be_empty
      expect(entitlement.reload).to be_withdrawn
    end

    it "withdraws exactly that actor's notifications" do
      notification = create(:notification, user: recipient.user, actor: remote)
      other_notification = create(
        :notification,
        user: recipient.user,
        actor: other_remote,
        subject: create(:following, follower_actor: other_remote, followed_actor: recipient)
      )

      described_class.new.block_actor!(actor_uri: remote.uri)

      expect(Notification.where(id: notification.id)).not_to exist
      expect(Notification.where(id: other_notification.id)).to exist
    end
  end
end
