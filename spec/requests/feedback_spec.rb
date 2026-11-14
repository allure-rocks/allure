# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Feedback", type: :request do
  let(:user) { create(:user, email_address: "rider@example.com") }
  let(:config) do
    Allure::Gitlab::Config.new(
      enabled: true,
      api_url: "https://gitlab.example/api/v4",
      project_id: "group/allure",
      token: "secret-token"
    )
  end
  let(:png_base64) do
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
  end
  let(:png_data_uri) { "data:image/png;base64,#{png_base64}" }

  before do
    allow(Allure::Gitlab).to receive(:config).and_return(config)
  end

  describe "POST /feedback" do
    it "requires a logged-in user" do
      post feedback_path, params: { description: "Broken page", screenshot: png_data_uri }, as: :json

      expect(response).to redirect_to(new_session_path)
    end

    it "creates an issue through the GitLab service" do
      sign_in_as(user)
      service = instance_double(Feedback::GitlabIssueService)
      allow(Feedback::GitlabIssueService).to receive(:new).and_return(service)
      allow(service).to receive(:create_issue!).and_return("https://gitlab.example/issues/1")

      post feedback_path, params: {
        description: "Please improve this screen",
        screenshot: png_data_uri,
        pagePath: "/workouts/abc?private=1",
        userAgent: "RSpec",
        viewport: "1200x800"
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("issueUrl" => "https://gitlab.example/issues/1")
      expect(service).to have_received(:create_issue!).with(
        description: "Please improve this screen",
        screenshot_base64: png_base64,
        reporter: "rider@example.com",
        page_path: "/workouts/abc",
        user_agent: "RSpec",
        viewport: "1200x800"
      )
    end

    it "rejects submissions when GitLab is disabled" do
      sign_in_as(user)
      allow(Allure::Gitlab).to receive(:config).and_return(Allure::Gitlab::Config.new(enabled: false))

      post feedback_path, params: { description: "Broken page", screenshot: png_data_uri }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["errors"]).to include("Les signalements sont désactivés.")
    end

    it "rejects submissions when GitLab is incomplete" do
      sign_in_as(user)
      allow(Allure::Gitlab).to receive(:config).and_return(
        Allure::Gitlab::Config.new(enabled: true, project_id: "", token: "")
      )

      post feedback_path, params: { description: "Broken page", screenshot: png_data_uri }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include("Le signalement GitLab n'est pas configuré.")
    end

    it "rejects non-PNG screenshots" do
      sign_in_as(user)

      post feedback_path, params: {
        description: "Broken page",
        screenshot: "data:image/png;base64,#{Base64.strict_encode64("not png")}"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include("La capture doit être une image PNG.")
    end

    it "returns a retryable error when GitLab submission fails" do
      sign_in_as(user)
      service = instance_double(Feedback::GitlabIssueService)
      allow(Feedback::GitlabIssueService).to receive(:new).and_return(service)
      allow(service).to receive(:create_issue!).and_raise(Feedback::GitlabIssueService::Error, "boom")

      post feedback_path, params: { description: "Broken page", screenshot: png_data_uri }, as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["errors"]).to include("L'issue GitLab n'a pas pu être créée")
    end
  end

  describe "global widget" do
    it "is not rendered for anonymous visitors" do
      get feed_path

      expect(response.body).not_to include('data-controller="feedback"')
    end

    it "is rendered for signed-in users when GitLab is configured" do
      sign_in_as(user)
      get feed_path

      expect(response.body).to include('data-controller="feedback"', "Signaler un problème")
    end
  end

  describe "parameter filtering" do
    it "filters screenshot payloads from Rails logs" do
      parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = parameter_filter.filter(
        "screenshot" => png_data_uri,
        "screenshot_base64" => png_base64
      )

      expect(filtered).to eq(
        "screenshot" => "[FILTERED]",
        "screenshot_base64" => "[FILTERED]"
      )
    end
  end
end
