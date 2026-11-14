# frozen_string_literal: true

require "rails_helper"

# PLAN_TOGETHER.md §8: a detected outing is answered by both accounts, each
# from their own workout; the counterpart's workout stays closed until both
# confirmed.
RSpec.describe "Co-presence suggestions" do
  let(:marie) { create(:user, username: "marie") }
  let(:paul) { create(:user, username: "paul") }
  let!(:marie_actor) { create(:local_actor, user: marie) }
  let!(:paul_actor) { create(:local_actor, user: paul) }
  let(:source) { create(:workout, user: marie, title: "Sortie de Marie", distance: 42_000) }
  let(:recording) { create(:workout, user: paul, title: "Sortie de Paul") }
  let!(:participation) do
    create(:workout_participation, workout: source, participant_actor: paul_actor, participant_workout: recording,
                                   kind: "link", origin: "detection", owner_confirmed_at: nil,
                                   participant_confirmed_at: nil)
  end

  def answer(path_workout, decision)
    patch workout_participation_path(path_workout, participation), params: { decision: },
                                                                    headers: { "HTTP_REFERER" => workout_url(answered_from) }
  end

  describe "the counterpart" do
    before { sign_in_as(paul) }

    let(:answered_from) { recording }

    it "cannot open the other workout before both confirmed" do
      get workout_path(source)

      expect(response).to have_http_status(:not_found)
    end

    it "answers from their own recording's card and returns there" do
      get workout_path(recording)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.suggestion_notice")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.states.suggested")))
      expect(response.body).not_to include("Sortie de Marie", "42,00 km", "42.00 km")

      answer(source, "confirm")

      expect(response).to redirect_to(workout_url(recording))
      expect(participation.reload.participant_confirmed_at).to be_present
    end

    it "opens their own recording from the suggestion notice" do
      notice = create(:notification, user: paul, kind: "participation_suggested", actor: marie_actor, subject: participation)

      get notification_path(notice)

      expect(response).to redirect_to(workout_path(recording))
    end

    it "reads the source once both confirmed" do
      participation.update!(owner_confirmed_at: Time.current, participant_confirmed_at: Time.current)

      get workout_path(source)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the source's owner" do
    before { sign_in_as(marie) }

    let(:answered_from) { source }

    it "answers from their own card" do
      get workout_path(source)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.suggestion_notice")))

      answer(source, "decline")

      expect(response).to redirect_to(workout_url(source))
      expect(participation.reload).to be_declined
    end
  end

  it "answers 404 to anyone else" do
    sign_in_as(create(:user))

    patch workout_participation_path(source, participation), params: { decision: "confirm" }

    expect(response).to have_http_status(:not_found)
  end

  describe "a credit-to-link suggestion" do
    let(:credit_source) { create(:workout, user: marie, title: "Le tour de Marie") }
    let(:own) { create(:workout, user: paul, title: "Ma montre") }
    let!(:credit_participation) do
      create(:workout_participation, workout: credit_source, participant_actor: paul_actor, suggested_workout: own)
    end
    let!(:credit) { Participations::CreditRows.attach(credit_participation) }

    before { sign_in_as(paul) }

    it "shows on the recording and on the credit row, and links in one click" do
      get workout_path(own)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.link_suggestion.title")))

      get workout_path(credit)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.link_suggestion.title")))

      patch convert_workout_participation_path(credit_source, credit_participation),
            params: { participant_workout_id: own.to_param }

      expect(response).to redirect_to(workout_path(own))
      expect(credit_participation.reload.kind).to eq("link")
      expect(Workout.exists?(credit.id)).to be(false)
    end

    it "is dismissed for good" do
      patch dismiss_link_suggestion_workout_participation_path(credit_source, credit_participation),
            headers: { "HTTP_REFERER" => workout_url(own) }

      expect(response).to redirect_to(workout_url(own))
      expect(credit_participation.reload.link_suggestion_dismissed_at).to be_present
      get workout_path(own)
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("workouts.participations.link_suggestion.title")))
    end

    it "is refused to the credit's owner" do
      sign_in_as(marie)

      patch dismiss_link_suggestion_workout_participation_path(credit_source, credit_participation)

      expect(response).to have_http_status(:not_found)
    end
  end

  it "offers the opt-out switch in the notification settings" do
    sign_in_as(paul)

    patch settings_notifications_path, params: { user: { together_detection_enabled: "0" } }

    expect(paul.reload.together_detection_enabled).to be(false)
  end
end
