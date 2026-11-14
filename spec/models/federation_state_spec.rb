# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Federation durable state" do
  let!(:local_actor) { create(:local_actor) }
  let!(:remote_actor) { create(:actor) }

  describe Following do
    it "models a directed pending relationship" do
      following = create(:following, follower_actor: local_actor, followed_actor: remote_actor)

      expect(following).to be_pending
      expect(following).to be_active
      expect(following).not_to be_eligible_for_follower_access
    end

    it "accepts and undoes a relationship with matching timestamps" do
      following = create(:following, follower_actor: remote_actor, followed_actor: local_actor)

      following.accept!
      expect(following.reload).to be_accepted
      expect(following.accepted_at).to be_present
      expect(following).to be_eligible_for_follower_access

      following.undo!
      expect(following.reload).to be_undone
      expect(following.undone_at).to be_present
      expect(following).not_to be_active
    end

    it "provides canonical accepted relationship scopes" do
      accepted = create(:following, :accepted, follower_actor: remote_actor, followed_actor: local_actor)
      create(:following, follower_actor: local_actor, followed_actor: remote_actor)

      expect(Following.accepted_followers_of(local_actor)).to contain_exactly(accepted)
      expect(Following.accepted_following_of(remote_actor)).to contain_exactly(accepted)
      expect(Following.accepted_between(follower_actor: remote_actor, followed_actor: local_actor)).to contain_exactly(accepted)
    end

    it "allows a new relationship only after the previous one is undone" do
      create(:following, :accepted, follower_actor: local_actor, followed_actor: remote_actor)

      expect {
        create(:following, follower_actor: local_actor, followed_actor: remote_actor)
      }.to raise_error(ActiveRecord::RecordInvalid)

      old = Following.find_by!(follower_actor: local_actor, followed_actor: remote_actor)
      old.undo!
      expect {
        create(:following, follower_actor: local_actor, followed_actor: remote_actor)
      }.to change(Following, :count).by(1)
    end

    it "rejects self-following at the model and database boundaries" do
      expect(build(:following, follower_actor: local_actor, followed_actor: local_actor)).not_to be_valid

      expect {
        Following.insert_all!([ {
          follower_actor_id: local_actor.id,
          followed_actor_id: local_actor.id,
          uri: "https://remote.example/activities/self",
          status: "pending",
          requested_at: Time.current,
          created_at: Time.current,
          updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::StatementInvalid, /followings_no_self_follow/)
    end
  end

  describe FederationInboxItem do
    it "owns attempts and exponential backoff durably" do
      now = Time.utc(2026, 8, 26, 12)
      item = create(:federation_inbox_item, next_attempt_at: now)

      expect(item.claim!(now:)).to be(true)
      expect(item.reload.attempts).to eq(1)
      expect(item.status).to eq("processing")

      expect(item.retry!(error: "temporary failure", now:)).to be(true)
      expect(item.reload.status).to eq("pending")
      expect(item.next_attempt_at).to eq(now + 5.minutes)
    end

    it "stops after ten processing attempts" do
      item = create(:federation_inbox_item, attempts: 10, status: "processing")

      expect(item.retry!(error: "permanent failure")).to be(false)
      expect(item.reload).to be_failed
    end

    it "fails a due item instead of exceeding the attempt limit" do
      item = create(:federation_inbox_item, attempts: FederationInboxItem::MAX_ATTEMPTS)

      expect(item.claim!).to be(false)
      expect(item.reload).to be_failed
    end
  end

  describe FederationOutboxEvent do
    it "stores a stable activity snapshot" do
      event = create(:federation_outbox_event)

      expect(event.activity_uri).to include("/activities/#{event.event_uuid}")
      expect(event.payload).to be_a(Hash)
      expect(event.audience).to include("to")
      expect { event.update!(payload: { "private" => true }) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    it "requires an explicit publication subject for publication events" do
      publication = create(:workout_publication)
      event = build(
        :federation_outbox_event,
        actor: publication.actor,
        subject_type: "WorkoutPublication",
        subject_id: publication.id,
        workout_publication_id: publication.id,
        activity_type: "Create",
        object_uri: publication.object_uri
      )
      event.workout_publication_id = nil

      expect(event).not_to be_valid
      expect(event.errors[:workout_publication]).to be_present
    end

    it "rejects an explicit publication subject on actor events" do
      publication = create(:workout_publication)
      event = build(
        :federation_outbox_event,
        subject_type: "Actor",
        subject_id: local_actor.id,
        workout_publication_id: publication.id
      )

      expect(event).not_to be_valid
    end

    it "keeps subject references immutable" do
      publication = create(:workout_publication)
      event = create(
        :federation_outbox_event,
        actor: publication.actor,
        subject_type: "WorkoutPublication",
        subject_id: publication.id,
        workout_publication_id: publication.id,
        activity_type: "Create",
        object_uri: publication.object_uri
      )

      expect { event.update!(subject_id: publication.id + 1) }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { event.update!(workout_publication_id: nil) }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    it "prevents mismatched publication subjects at the database boundary" do
      publication = create(:workout_publication)
      other = create(:workout_publication)

      expect {
        FederationOutboxEvent.where(id: create(
          :federation_outbox_event,
          actor: publication.actor,
          subject_type: "WorkoutPublication",
          subject_id: publication.id,
          workout_publication_id: publication.id,
          activity_type: "Create",
          object_uri: publication.object_uri
        ).id).update_all(subject_id: other.id)
      }.to raise_error(ActiveRecord::StatementInvalid, /outbox_publication_subject_integrity/)
    end

    it "requires an explicit segment publication subject for segment events" do
      segment_publication = create(:segment_publication, :with_gpx)
      event = build(
        :federation_outbox_event,
        actor: segment_publication.actor,
        subject_type: "SegmentPublication",
        subject_id: segment_publication.id,
        segment_publication_id: segment_publication.id,
        activity_type: "Create",
        object_uri: segment_publication.object_uri
      )
      expect(event).to be_valid

      event.segment_publication_id = nil
      expect(event).not_to be_valid
      expect(event.errors[:segment_publication]).to be_present
    end

    it "rejects a crossed publication subject on segment events" do
      segment_publication = create(:segment_publication, :with_gpx)
      workout_publication = create(:workout_publication)
      event = build(
        :federation_outbox_event,
        actor: segment_publication.actor,
        subject_type: "SegmentPublication",
        subject_id: segment_publication.id,
        segment_publication_id: segment_publication.id,
        workout_publication_id: workout_publication.id,
        activity_type: "Create",
        object_uri: segment_publication.object_uri
      )

      expect(event).not_to be_valid
    end
  end

  describe FederationDelivery do
    it "claims a delivery with a lease and records a response without a body" do
      now = Time.utc(2026, 8, 26, 12)
      delivery = create(:federation_delivery)

      expect(delivery.claim!(now:)).to be(true)
      expect(delivery.reload).to be_delivering
      expect(delivery.attempts).to eq(1)
      expect(delivery.lease_until).to eq(now + 5.minutes)

      delivery.mark_delivered!(response_status: 202, at: now)
      expect(delivery.reload).to be_delivered
      expect(delivery.last_response_status).to eq(202)
      expect(delivery.delivered_at).to eq(now)
    end

    it "retries temporary failures with a capped schedule" do
      now = Time.utc(2026, 8, 26, 12)
      delivery = create(:federation_delivery, attempts: 1, status: "delivering")

      expect(delivery.retry!(error: "timeout", response_status: 503, now:)).to be(true)
      expect(delivery.reload).to be_retrying
      expect(delivery.next_attempt_at).to eq(now + 5.minutes)
    end

    it "fails a delivery instead of exceeding the attempt limit" do
      delivery = create(:federation_delivery, attempts: FederationDelivery::MAX_ATTEMPTS)

      expect(delivery.claim!).to be(false)
      expect(delivery.reload).to be_failed
    end
  end
end
