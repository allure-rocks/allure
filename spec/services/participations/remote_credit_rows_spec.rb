# frozen_string_literal: true

require "rails_helper"

# docs/dev/SHARED-ACTIVITIES.md: a confirmed invitation from another
# instance counts for the account through a credit row built from the
# received note's figures, removed with the participation, detached and kept
# when the note is deleted, re-attached for the republished outing.
RSpec.describe Participations::RemoteCreditRows do
  include ActiveJob::TestHelper

  let(:paul) { create(:user, username: "paul") }
  let!(:paul_actor) { create(:local_actor, user: paul) }
  let(:sport) { catalog_sport("hiking") }
  let(:owner_actor) do
    create(:actor, uri: "https://remote.example/users/marie", inbox_url: "https://remote.example/inbox",
                   display_name: "Marie", handle: "marie", acct: "marie@remote.example")
  end
  let(:figures) do
    { "distance" => 21_500.0, "duration" => 25_200.0, "moving_time" => 22_000.0, "ascent" => 1_250.0,
      "descent" => 1_240.0, "average_speed" => 0.98, "max_speed" => 2.4, "average_heart_rate" => 140 }
  end
  let(:note) { received_note }
  let!(:participation) { invited(note) }

  def received_note(started_at: Time.utc(2026, 8, 26, 8))
    remote_note = create(:remote_note, actor: owner_actor, title: "Traversée", metrics: figures, started_at:)
    create(:remote_note_recipient, remote_note:, recipient_actor: paul_actor)
    remote_note
  end

  def invited(remote_note, uri: "#{owner_actor.uri}/activities/invite-#{remote_note.id}")
    RemoteParticipation.create!(remote_note:, recipient_actor: paul_actor, object_uri: remote_note.object_uri,
                                invite_activity_uri: uri, sport_slug: sport.slug, started_at: remote_note.started_at)
  end

  def confirm(row = participation) = Participations::RemoteAnswer.new(participation: row, user: paul, decision: "confirm").call!

  def credit = paul.workouts.credit_rows_only.sole

  it "builds the credit row from the note's figures and the Invite's sport, counting for the account" do
    confirm

    expect(credit).to have_attributes(
      remote_participation: participation, credited_by: owner_actor, sport:, title: "Traversée",
      started_at: note.started_at, duration: 25_200, moving_time: 22_000, pause_time: 3_200, average_heart_rate: nil
    )
    expect(credit.distance.to_f).to eq(21_500)
    expect(credit).to be_credit_remote
    expect(credit).not_to be_credit_detached
    expect(credit.track_workout).to be_nil
    expect(Record.find_by!(user: paul, sport:, record_type: "HA").workout).to eq(credit)
  end

  it "confirms nothing when the credit row cannot be built" do
    allow(described_class).to receive(:attach).and_raise(ActiveRecord::RecordInvalid)

    expect { confirm }.to raise_error(ActiveRecord::RecordInvalid)

    expect(participation.reload).to be_pending
    expect(FederationOutboxEvent.where(actor: paul_actor, activity_type: "Accept")).to be_empty
  end

  it "builds nothing when a credited figure is missing" do
    figures.delete("ascent")
    partial = invited(received_note(started_at: Time.utc(2026, 9, 1, 8)))

    confirm(partial)

    expect(paul.workouts.credit_rows_only).to be_empty
  end

  it "goes with the participation when the account withdraws, telling the owner" do
    confirm
    Participations::RemoteAnswer.new(participation:, user: paul, decision: "withdraw").call!

    expect(paul.workouts.credit_rows_only).to be_empty
    expect(Record.where(user: paul)).to be_empty
  end

  it "withdraws the participation, with an Undo of the Accept, when the account removes the row" do
    confirm

    Workouts::WorkoutDeletion.new(user: paul, workout: credit).call!

    expect(participation.reload).to be_withdrawn
    expect(FederationOutboxEvent.where(actor: paul_actor, activity_type: "Undo").sole.payload.dig("object", "type"))
      .to eq("Accept")
  end

  it "goes when the owner withdraws the invitation" do
    confirm

    Participations::RemoteWithdrawal.withdraw!(participation)

    expect(paul.workouts.credit_rows_only).to be_empty
  end

  it "is detached and kept when the note is deleted, then re-attached for the republished outing" do
    confirm
    kept = credit
    Participations::RemoteWithdrawal.close_pending!(RemoteNote.where(id: note.id).tap { note.mark_deleted! })

    expect(kept.reload).to be_credit_detached
    expect(kept.title).to be_nil
    expect(Notification.find_by!(user: paul, kind: "participation_source_deleted").subject).to eq(kept)
    expect(Record.find_by!(user: paul, sport:, record_type: "HA").workout).to eq(kept)

    # The owner's Undo of the old invitation keeps the detached credit.
    Participations::RemoteWithdrawal.withdraw!(participation)
    expect(kept.reload).to be_persisted

    republished = received_note(started_at: note.started_at + 30.seconds)
    confirm(invited(republished, uri: "#{owner_actor.uri}/activities/invite-again"))

    expect(credit).to eq(kept)
    expect(kept.reload).not_to be_credit_detached
    expect(kept.remote_participation.remote_note).to eq(republished)
  end

  describe "the credit row page", type: :request do
    before do
      confirm
      sign_in_as(paul)
    end

    it "links the badge to the received note while it lives, and says when it is gone" do
      get workout_path(credit)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(remote_note_path(note), "Avec Marie")

      Participations::RemoteWithdrawal.close_pending!(RemoteNote.where(id: note.id).tap { note.mark_deleted! })
      get workout_path(credit)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.credit.route_gone")))
      expect(response.body).not_to include(remote_note_path(note))
    end

    it "tells REST clients who recorded it", type: :request do
      headers = api_headers_for(paul, scopes: %w[read])
      get "/api/rest/v1/workouts/#{credit.to_param}", headers: headers

      expect(response.parsed_body["credit"]).to include("source_deleted" => false)
      expect(response.parsed_body["credit"]["recorded_by"]).to include("handle" => "marie@remote.example")
    end
  end
end
