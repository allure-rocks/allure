# frozen_string_literal: true

require "rails_helper"

# Assistant consent and the deletion of the stored summaries (docs/dev/AI.md).
RSpec.describe "Assistant settings" do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "is not found while the instance offers no assistant" do
    get settings_assistant_path

    expect(response).to have_http_status(:not_found)
  end

  context "when the instance offers it", :assistant do
    it "is off by default and states what happens to the measurements" do
      get settings_assistant_path

      expect(response).to have_http_status(:ok)
      expect(user.ai_enabled).to be(false)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("assistant.notice")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.assistant.privacy")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.assistant.enrichment_label")))
    end

    it "offers the recent backfill once consent is given" do
      create(:workout, user:, started_at: 2.days.ago)
      get settings_assistant_path
      expect(response.body).not_to include(I18n.t("settings.assistant.backfill.title"))

      user.update!(ai_enabled: true)
      get settings_assistant_path

      expect(response.body).to include(I18n.t("settings.assistant.backfill.title"))
      expect(response.body).to include(settings_data_summaries_path)
    end

    it "turns on and off without touching the stored summaries" do
      workout = create(:workout, user:)
      create(:workout_summary, :ready, workout:)

      patch settings_assistant_path, params: { user: { ai_enabled: "1" } }
      expect(response).to redirect_to(settings_assistant_path)
      expect(flash[:notice]).to eq(I18n.t("settings.assistant.update.enabled"))
      expect(user.reload.ai_enabled).to be(true)

      patch settings_assistant_path, params: { user: { ai_enabled: "0" } }
      expect(flash[:notice]).to eq(I18n.t("settings.assistant.update.disabled"))
      expect(user.reload.ai_enabled).to be(false)
      expect(workout.reload.assistant_summary).to be_present
    end

    it "deletes the account's summaries and nobody else's" do
      own = create(:workout, user:)
      create(:workout_summary, :ready, workout: own)
      other = create(:workout_summary, :ready, workout: create(:workout, user: create(:user)))

      delete settings_assistant_path

      expect(response).to redirect_to(settings_assistant_path)
      expect(flash[:notice]).to eq(I18n.t("settings.assistant.destroy.success", count: 1))
      expect(own.reload.assistant_summary).to be_nil
      expect(WorkoutSummary.exists?(other.id)).to be(true)
    end

    it "counts the stored summaries on the page" do
      create(:workout_summary, :ready, workout: create(:workout, user:))
      create(:workout_summary, :ready, workout: create(:workout, user:))

      get settings_assistant_path

      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("settings.assistant.stored.description", count: 2))
      )
    end
  end

  describe "the settings navigation" do
    it "links the page only while the instance offers the assistant" do
      get settings_path
      expect(response.body).not_to include(settings_assistant_path)

      user.update!(ai_enabled: true)
      with_env("AI_BASE_URL" => AssistantHelpers::BASE_URL, "AI_MODEL" => AssistantHelpers::MODEL) do
        get settings_path
        expect(response.body).to include(settings_assistant_path)
      end
    end
  end

  def with_env(values)
    previous = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
