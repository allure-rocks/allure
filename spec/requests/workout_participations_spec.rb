# frozen_string_literal: true

require "rails_helper"

# Shared activities (docs/dev/SHARED-ACTIVITIES.md, DESIGN.md §10.18): the owner
# invites an accepted follow, the participant confirms or declines from the
# metrics-only presentation, and everyone else gets a 404.
RSpec.describe "Workout participations" do
  let(:owner) { create(:user, username: "marie") }
  let(:participant) { create(:user, username: "paul") }
  let(:stranger) { create(:user, username: "zoe") }
  let(:owner_actor) { create(:actor, :local, user: owner) }
  let(:participant_actor) { create(:actor, :local, user: participant) }
  let(:workout) do
    create(:workout, user: owner, title: "Sortie du soir",
                     source: "Garmin Secret", description: "Notes du propriétaire",
                     average_heart_rate: 140)
  end

  def follow_accepted!
    owner_actor
    participant_actor
    create(:following, :accepted, follower_actor: participant_actor, followed_actor: owner_actor)
  end

  def invite!
    create(:workout_participation, :pending, workout:, participant_actor:)
  end

  describe "the owner" do
    before { sign_in_as(owner) }

    it "sees the participants card with the invitation copy" do
      follow_accepted!

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.title")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.invite_hint")))
    end

    it "names each confirmed participant with the « Avec @X » badge, on the page and the card" do
      recording = create(:workout, user: participant, started_at: workout.started_at)
      create(:workout_participation, :link, workout:, participant_actor:, participant_workout: recording)
      # A pending invitation names nobody yet.
      create(:workout_participation, :pending, workout:, participant_actor: create(:actor, :local, user: stranger))

      get workout_path(workout)

      badges = response.parsed_body.css(".page-pretitle [data-badge='together']")
      expect(badges.map(&:text).map(&:strip)).to eq([ "Avec #{participant.display_name}" ])
      # The badge names the participant; it never opens their profile.
      expect(badges.first.name).to eq("span")
      expect(badges.first["href"]).to be_nil

      get workouts_path
      card = response.parsed_body.css(".card").find { |node| node.text.include?("Sortie du soir") }
      expect(card.at_css(".workout-card__badges [data-badge='together'].allure-badge-icon")["data-bs-title"])
        .to eq("Avec #{participant.display_name}")
    end

    it "joins several participants in one badge, naming everyone in its tooltip" do
      names = %w[Eva Joan Inès].map do |name|
        user = create(:user, username: name.downcase.tr("è", "e"), display_name: name)
        create(:workout_participation, workout:, participant_actor: create(:actor, :local, user:))
        name
      end

      get workout_path(workout)

      badges = response.parsed_body.css(".page-pretitle [data-badge='together']")
      expect(badges.size).to eq(1)
      expect(badges.first.name).to eq("span")
      expect(badges.first.text.strip).to eq("Avec Eva et 2 autres")
      expect(badges.first["data-bs-title"]).to eq("Avec #{names[0]}, #{names[1]} et #{names[2]}")

      get workouts_path
      card = response.parsed_body.css(".card").find { |node| node.text.include?("Sortie du soir") }
      icons = card.css(".workout-card__badges [data-badge='together']")
      expect(icons.size).to eq(1)
      expect(icons.first["data-bs-title"]).to eq("Avec Eva, Joan et Inès")
    end

    it "invites an accepted follow" do
      follow_accepted!

      expect {
        post workout_participations_path(workout), params: { participation: { handle: "paul" } }
      }.to change(WorkoutParticipation, :count).by(1)

      expect(response).to redirect_to(workout_path(workout))
      expect(flash[:notice]).to eq(I18n.t("workouts.participations.notices.proposed"))
      expect(Notification.where(user: participant, kind: "participation_requested")).to exist
    end

    it "refuses an account outside the follow gate" do
      participant_actor

      expect {
        post workout_participations_path(workout), params: { participation: { handle: "paul" } }
      }.not_to change(WorkoutParticipation, :count)

      expect(flash[:alert]).to eq(I18n.t("workouts.participations.notices.not_allowed"))
    end

    it "names the remote conditions when a remote handle is refused" do
      allow_any_instance_of(Participations::Propose).to receive(:call!)
        .and_raise(Participations::Propose::NotAllowed, "does not hold")

      post workout_participations_path(workout), params: { participation: { handle: "@paul@remote.example" } }

      expect(flash[:alert]).to eq(I18n.t("workouts.participations.notices.not_allowed_remote"))
    end

    it "withdraws a live participation" do
      participation = invite!

      expect {
        delete workout_participation_path(workout, participation)
      }.not_to change(WorkoutParticipation, :count)

      expect(participation.reload).to be_withdrawn
      expect(response).to redirect_to(workout_path(workout))
    end

    it "re-invites after a withdrawal without error" do
      follow_accepted!
      participation = invite!
      delete workout_participation_path(workout, participation)

      expect {
        post workout_participations_path(workout), params: { participation: { handle: "paul" } }
      }.to change { WorkoutParticipation.live.count }.by(1)

      expect {
        post workout_participations_path(workout), params: { participation: { handle: "paul" } }
      }.not_to change(WorkoutParticipation, :count)

      expect(response).to redirect_to(workout_path(workout))
    end

    it "renders a tombstoned participant as a deleted account" do
      invite!
      handle = ApplicationController.helpers.actor_handle(participant_actor)
      participant_actor.tombstone!

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.deleted_account")))
      expect(response.body).not_to include(handle)
    end

    it "cannot answer an invitation" do
      participation = invite!

      patch workout_participation_path(workout, participation), params: { decision: "confirm" }

      expect(response).to have_http_status(:not_found)
      expect(participation.reload).not_to be_confirmed
    end
  end

  describe "the participant" do
    before do
      follow_accepted!
      sign_in_as(participant)
    end

    it "gets the metrics-only presentation without the source's private data" do
      invite!

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.confirm_notice")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.metrics_hint")))
      expect(response.body).to include("Avec #{owner.display_name}")
      expect(response.body).not_to include("Garmin Secret")
      expect(response.body).not_to include("Notes du propriétaire")
      expect(response.body).not_to include(
        ERB::Util.html_escape(I18n.t("workouts.show.metrics.average_heart_rate"))
      )
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("workouts.show.map.title")))
    end

    it "reads the publication presentation once the source is published" do
      invite!
      create(:track_segment, workout:)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      publish_workout!(user: owner, workout:, profile:)

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Notes du propriétaire")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.show.map.title")))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("workouts.participations.metrics_hint")))
      expect(response.body).to include("Avec #{owner.display_name}")
    end

    it "confirms the invitation and notifies the owner" do
      participation = invite!

      patch workout_participation_path(workout, participation), params: { decision: "confirm" }

      expect(response).to redirect_to(workout_path(workout))
      expect(participation.reload).to be_confirmed
      expect(Notification.where(user: owner, kind: "participation_confirmed")).to exist
    end

    it "names their own recording when confirming, which makes a link" do
      participation = invite!
      recording = create(:workout, user: participant, title: "Ma sortie", started_at: workout.started_at + 10.minutes)

      get workout_path(workout)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.recording_label")))
      expect(response.body).to include("Ma sortie")

      patch workout_participation_path(workout, participation),
            params: { decision: "confirm", participant_workout_id: recording.to_param }

      participation.reload
      expect(participation).to be_confirmed
      expect(participation.kind).to eq("link")
      expect(participation.participant_workout).to eq(recording)
    end

    it "cannot name another account's workout" do
      participation = invite!
      foreign = create(:workout, user: owner, started_at: workout.started_at)

      patch workout_participation_path(workout, participation),
            params: { decision: "confirm", participant_workout_id: foreign.to_param }

      expect(response).to have_http_status(:not_found)
      expect(participation.reload).not_to be_confirmed
    end

    it "converts a confirmed credit into a link" do
      participation = create(:workout_participation, workout:, participant_actor:)
      recording = create(:workout, user: participant, started_at: workout.started_at)

      get workout_path(workout)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.convert")))

      patch convert_workout_participation_path(workout, participation),
            params: { participant_workout_id: recording.to_param }

      expect(response).to redirect_to(workout_path(recording))
      expect(flash[:notice]).to eq(I18n.t("workouts.participations.notices.converted"))
      expect(participation.reload.kind).to eq("link")
    end

    it "shows the link badge on their own linked recording" do
      recording = create(:workout, user: participant, started_at: workout.started_at)
      create(:workout_participation, :link, workout:, participant_actor:, participant_workout: recording)

      get workout_path(recording)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Avec #{owner.display_name}")
      expect(response.body).to include(workout_path(workout))
    end

    it "declines the invitation" do
      participation = invite!

      patch workout_participation_path(workout, participation), params: { decision: "decline" }

      expect(participation.reload).to be_declined
      expect(response).to redirect_to(workout_path(workout))
    end

    it "withdraws their confirmed participation" do
      participation = create(:workout_participation, workout:, participant_actor:)

      delete workout_participation_path(workout, participation)

      expect(participation.reload).to be_withdrawn
    end

    it "cannot invite on someone else's workout" do
      expect {
        post workout_participations_path(workout), params: { participation: { handle: "zoe" } }
      }.not_to change(WorkoutParticipation, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "loses access once the participation is withdrawn" do
      participation = invite!
      participation.update!(withdrawn_at: Time.current)

      get workout_path(workout)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "everyone else" do
    before do
      follow_accepted!
      sign_in_as(stranger)
    end

    it "cannot open an unpublished source workout" do
      invite!

      get workout_path(workout)

      expect(response).to have_http_status(:not_found)
    end

    it "cannot answer or withdraw a participation" do
      participation = invite!

      patch workout_participation_path(workout, participation), params: { decision: "confirm" }
      expect(response).to have_http_status(:not_found)

      delete workout_participation_path(workout, participation)
      expect(response).to have_http_status(:not_found)

      expect(participation.reload).to be_active
    end
  end

  it "redirects an anonymous visitor to sign-in" do
    workout

    get workout_path(workout)

    expect(response).to redirect_to(new_session_path)
  end
end
