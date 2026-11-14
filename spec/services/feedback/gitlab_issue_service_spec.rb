# frozen_string_literal: true

require "rails_helper"

RSpec.describe Feedback::GitlabIssueService do
  let(:config) do
    Allure::Gitlab::Config.new(
      enabled: true,
      api_url: "https://gitlab.example/api/v4",
      project_id: "group/allure",
      token: "secret-token",
      labels: [ "feedback", "allure" ],
      confidential: true
    )
  end
  let(:service) { described_class.new(config:) }
  let(:png_base64) do
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
  end

  describe "#create_issue!" do
    it "uploads the screenshot and creates a GitLab issue" do
      upload_request = stub_request(:post, "https://gitlab.example/api/v4/projects/group%2Fallure/uploads")
        .to_return(status: 201, body: { markdown: "![screenshot](/uploads/screenshot.png)" }.to_json)
      issue_request = stub_request(:post, "https://gitlab.example/api/v4/projects/group%2Fallure/issues")
        .with { |request| request.body.include?("Broken%20page") && request.body.include?("labels=feedback%2Callure") }
        .to_return(status: 201, body: { web_url: "https://gitlab.example/group/allure/-/issues/1" }.to_json)

      issue_url = service.create_issue!(
        description: "Broken page",
        screenshot_base64: png_base64,
        reporter: "rider@example.com",
        page_path: "/workouts/abc",
        user_agent: "RSpec",
        viewport: "1200x800"
      )

      expect(issue_url).to eq("https://gitlab.example/group/allure/-/issues/1")
      expect(upload_request).to have_been_requested
      expect(issue_request).to have_been_requested
      expect(
        a_request(:post, "https://gitlab.example/api/v4/projects/group%2Fallure/uploads")
          .with(headers: { "PRIVATE-TOKEN" => "secret-token" })
      ).to have_been_requested
    end

    it "raises an error when GitLab rejects the issue" do
      stub_request(:post, "https://gitlab.example/api/v4/projects/group%2Fallure/uploads")
        .to_return(status: 201, body: { markdown: "![screenshot](/uploads/screenshot.png)" }.to_json)
      stub_request(:post, "https://gitlab.example/api/v4/projects/group%2Fallure/issues")
        .to_return(status: 400, body: { message: "invalid labels" }.to_json)

      expect {
        service.create_issue!(
          description: "Broken page",
          screenshot_base64: png_base64,
          reporter: nil,
          page_path: nil,
          user_agent: "RSpec",
          viewport: "1200x800"
        )
      }.to raise_error(described_class::Error, /GitLab API returned 400/)
    end

    it "rejects invalid base64 before making a request" do
      expect {
        service.create_issue!(
          description: "Broken page",
          screenshot_base64: "not-base64",
          reporter: nil,
          page_path: nil,
          user_agent: nil,
          viewport: nil
        )
      }.to raise_error(described_class::Error, /not valid base64/)
    end
  end
end
