# frozen_string_literal: true

require "rails_helper"

# The answers and withdrawals of a remote participation (PLAN_TOGETHER.md §7),
# on each side of the wire.
RSpec.describe "Remote participation answers" do
  def inbound(recipient, activity)
    item = create(:federation_inbox_item, recipient_actor: recipient, activity_uri: activity.fetch("id"),
                                          activity_type: activity.fetch("type"), actor_uri: activity.fetch("actor"),
                                          raw: activity)
    Federation::ProcessInboxItemJob.perform_now(item)
    item.reload
  end

  describe "on the owner's instance" do
    let(:owner) { create(:user) }
    let!(:owner_actor) { create(:local_actor, user: owner) }
    let(:workout) { create(:workout, user: owner) }
    let(:remote) { create(:actor, uri: "https://remote.example/users/paul", inbox_url: "https://remote.example/inbox") }
    let(:invite_uri) { "#{owner_actor.uri}/activities/invite-1" }
    let!(:participation) do
      create(:workout_participation, :pending, workout:, participant_actor: remote, wire_activity_uri: invite_uri)
    end

    def answer(type, id: "https://remote.example/activities/#{type.downcase}-1", actor: remote.uri, object: invite_uri)
      inbound(owner_actor, { "id" => id, "type" => type, "actor" => actor, "object" => object,
                             "to" => [ owner_actor.uri ], "cc" => [] })
    end

    it "confirms on the invited account's Accept and tells the owner" do
      expect(answer("Accept").status).to eq("processed")

      expect(participation.reload).to be_confirmed
      expect(Notification.find_by!(user: owner, kind: "participation_confirmed").actor).to eq(remote)
    end

    it "records a Reject as a terminal refusal" do
      answer("Reject")

      expect(participation.reload).to be_declined
    end

    it "withdraws on the account's Undo of its Accept" do
      answer("Accept")
      undo = { "type" => "Accept", "id" => "https://remote.example/activities/accept-1", "object" => invite_uri }

      expect(answer("Undo", id: "https://remote.example/activities/undo-1", object: undo).status).to eq("processed")
      expect(participation.reload).to be_withdrawn
      expect(Notification.where(kind: "participation_confirmed")).to be_empty
    end

    it "refuses an answer from anyone but the invited account" do
      item = answer("Accept", actor: create(:actor, uri: "https://remote.example/users/eve").uri)

      expect(item.status).to eq("rejected")
      expect(participation.reload).not_to be_confirmed
    end

    it "sends an Undo of the Invite where it was attempted when the owner withdraws" do
      publication = create(:workout_publication, workout:, actor: owner_actor)
      invite = create(:federation_outbox_event, actor: owner_actor, subject_type: "WorkoutPublication",
                                                subject_id: publication.id, activity_type: "Invite",
                                                object_uri: owner_actor.uri, status: "expanded",
                                                payload: { "type" => "Invite", "object" => publication.object_uri })
      participation.update_columns(wire_activity_uri: invite.activity_uri)
      delivery = create(:federation_delivery, outbox_event: invite, status: "delivered", attempts: 1)
      create(:federation_delivery_recipient, delivery:, actor_uri: remote.uri)

      Participations::Withdraw.new(participation:, user: owner).call!

      undo = FederationOutboxEvent.find_by!(activity_type: "Undo", actor: owner_actor)
      expect(undo.payload).to include("to" => [ remote.uri ])
      expect(undo.payload["object"]).to include("type" => "Invite", "id" => invite.activity_uri)
    end

    it "closes a pending invitation when its publication leaves or the participant unfollows" do
      publication = create(:workout_publication, workout:, actor: owner_actor)
      participation.update_columns(workout_publication_id: publication.id)
      other = create(:workout_participation, :pending, workout: create(:workout, user: owner),
                                                       participant_actor: remote, wire_activity_uri: "#{invite_uri}-2")

      publication.mark_deleted!
      expect(participation.reload).to be_withdrawn
      expect(other.reload).not_to be_withdrawn

      following = create(:following, :accepted, follower_actor: remote, followed_actor: owner_actor,
                                                uri: "https://remote.example/follows/1")
      inbound(owner_actor, { "id" => "https://remote.example/undo-follow", "type" => "Undo", "actor" => remote.uri,
                             "object" => { "type" => "Follow", "id" => following.uri }, "to" => [ owner_actor.uri ] })
      expect(other.reload).to be_withdrawn
    end

    it "cancels an Invite that never left instead of undoing it" do
      publication = create(:workout_publication, workout:, actor: owner_actor)
      invite = create(:federation_outbox_event, actor: owner_actor, subject_type: "WorkoutPublication",
                                                subject_id: publication.id, activity_type: "Invite",
                                                object_uri: owner_actor.uri, status: "pending")
      participation.update_columns(wire_activity_uri: invite.activity_uri)

      Participations::Withdraw.new(participation:, user: owner).call!

      expect(invite.reload).to be_cancelled
      expect(FederationOutboxEvent.where(activity_type: "Undo")).to be_empty
    end
  end

  describe "on the invited account's instance" do
    let(:paul) { create(:user, username: "paul") }
    let!(:paul_actor) { create(:local_actor, user: paul) }
    let(:owner_actor) do
      create(:actor, uri: "https://remote.example/users/marie", inbox_url: "https://remote.example/inbox",
                     display_name: "Marie", handle: "marie", acct: "marie@remote.example")
    end
    let(:note) { create(:remote_note, actor: owner_actor, title: "Sortie du soir") }
    let!(:entitlement) { create(:remote_note_recipient, remote_note: note, recipient_actor: paul_actor) }
    let(:invite_uri) { "#{owner_actor.uri}/activities/invite-1" }
    let!(:participation) do
      RemoteParticipation.create!(remote_note: note, recipient_actor: paul_actor, object_uri: note.object_uri,
                                  invite_activity_uri: invite_uri)
    end

    def answer(decision) = Participations::RemoteAnswer.new(participation:, user: paul, decision:).call!

    def sent(type) = FederationOutboxEvent.where(actor: paul_actor, activity_type: type)

    it "confirms with an Accept of the Invite addressed to the owner alone" do
      answer("confirm")

      expect(participation.reload).to be_confirmed
      event = sent("Accept").sole
      expect(event.payload).to include("type" => "Accept", "actor" => paul_actor.uri, "object" => invite_uri,
                                       "to" => [ owner_actor.uri ], "cc" => [])
      expect(event.activity_uri).to eq(Federation::Outbox::ParticipationAnswer.accept_uri_for(participation, paul_actor))
    end

    it "declines for good with a Reject" do
      answer("decline")

      expect(participation.reload).to be_declined
      expect(sent("Reject").sole.payload["object"]).to eq(invite_uri)
      expect { answer("confirm") }.to raise_error(Participations::RemoteAnswer::NotAllowed)
    end

    it "withdraws a confirmation with an Undo of its Accept" do
      answer("confirm")
      answer("withdraw")

      expect(participation.reload).to be_withdrawn
      undo = sent("Undo").sole
      expect(undo.payload["object"]).to include("type" => "Accept", "id" => sent("Accept").sole.activity_uri,
                                                "object" => invite_uri)
    end

    it "closes on the owner's Undo of the Invite, and refuses it from anyone else" do
      undo = { "type" => "Invite", "id" => invite_uri }
      stranger = create(:actor, uri: "https://remote.example/users/eve")

      expect(inbound(paul_actor, { "id" => "https://remote.example/u0", "type" => "Undo", "actor" => stranger.uri,
                                   "object" => undo, "to" => [ paul_actor.uri ] }).status).to eq("rejected")
      expect(inbound(paul_actor, { "id" => "https://remote.example/u1", "type" => "Undo", "actor" => owner_actor.uri,
                                   "object" => undo, "to" => [ paul_actor.uri ] }).status).to eq("processed")
      expect(participation.reload).to be_withdrawn
    end

    it "keeps a refusal when the owner undoes the invitation" do
      answer("decline")

      inbound(paul_actor, { "id" => "https://remote.example/u2", "type" => "Undo", "actor" => owner_actor.uri,
                            "object" => { "type" => "Invite", "id" => invite_uri }, "to" => [ paul_actor.uri ] })

      expect(participation.reload).to be_declined
      expect(participation).not_to be_withdrawn
    end

    it "ends with the invited account's deletion" do
      Users::DeleteAccount.new(user: paul).call!

      expect(participation.reload).to be_withdrawn
    end

    it "ends with an unfollow, telling the owner of a confirmation taken back" do
      create(:following, :accepted, follower_actor: paul_actor, followed_actor: owner_actor)
      answer("confirm")
      allow_any_instance_of(Federation::TargetResolver).to receive(:call!).and_return(owner_actor)

      Federation::Unfollow.new(user: paul, target: owner_actor.uri).call!

      expect(participation.reload).to be_withdrawn
      expect(sent("Undo").map { it.payload.dig("object", "type") }).to contain_exactly("Follow", "Accept")
    end

    it "ends with a block and tells nobody" do
      answer("confirm")

      Federation::Safety::Blocking.new.block_actor!(actor_uri: owner_actor.uri)

      expect(participation.reload).to be_withdrawn
      expect(sent("Undo")).to be_empty
    end

    it "closes a pending invitation when the note is deleted, and keeps a confirmed one" do
      other_note = create(:remote_note, actor: owner_actor)
      create(:remote_note_recipient, remote_note: other_note, recipient_actor: paul_actor)
      confirmed = RemoteParticipation.create!(remote_note: other_note, recipient_actor: paul_actor,
                                              object_uri: other_note.object_uri, invite_activity_uri: "#{invite_uri}-2",
                                              confirmed_at: Time.current)

      [ note, other_note ].each_with_index do |deleted, index|
        inbound(paul_actor, { "id" => "https://remote.example/d#{index}", "type" => "Delete", "actor" => owner_actor.uri,
                              "object" => deleted.object_uri, "to" => [ "https://www.w3.org/ns/activitystreams#Public" ] })
      end

      expect(participation.reload).to be_withdrawn
      expect(confirmed.reload).to be_confirmed
    end

    describe "the card on the received note", type: :request do
      before { sign_in_as(paul) }

      it "lets the invited account confirm, and nobody else find it" do
        get remote_note_path(note)
        expect(response.body).to include(ERB::Util.html_escape(I18n.t("remote_participations.invited", name: "Marie")))

        patch remote_participation_path(participation), params: { decision: "confirm" }
        expect(response).to redirect_to(remote_note_path(note))
        expect(participation.reload).to be_confirmed

        sign_in_as(create(:user))
        patch remote_participation_path(participation), params: { decision: "withdraw" }
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
