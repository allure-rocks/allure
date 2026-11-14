# frozen_string_literal: true

require "base64"
require "cgi"
require "httparty"
require "multipart/post"
require "tempfile"

module Feedback
  class GitlabIssueService
    include HTTParty

    class Error < StandardError; end

    MAX_DESCRIPTION_LENGTH = 10_000
    MAX_SCREENSHOT_BYTES = 8.megabytes
    MAX_RESPONSE_BYTES = 1.megabyte

    def initialize(config: Allure::Gitlab.config)
      @config = config
    end

    def create_issue!(description:, screenshot_base64:, reporter:, page_path:, user_agent:, viewport:)
      validate_config!

      upload = upload_screenshot!(screenshot_base64)
      response = self.class.post(issue_url, request_options.merge(body: issue_body(
        description: description,
        screenshot_markdown: upload.fetch("markdown"),
        reporter: reporter,
        page_path: page_path,
        user_agent: user_agent,
        viewport: viewport
      )))

      parsed = parse_response(response)
      return parsed.fetch("web_url") if response.success? && parsed["web_url"].present?

      raise Error, gitlab_error(response, parsed)
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
      raise Error, "GitLab request failed: #{e.message}"
    end

    private

    attr_reader :config

    def validate_config!
      config.validate!
      raise Error, "GitLab feedback is not configured" unless config.configured?
    rescue Allure::Gitlab::Config::InvalidConfiguration => e
      raise Error, e.message
    end

    def upload_screenshot!(screenshot_base64)
      file = Tempfile.new([ "allure-feedback", ".png" ])
      file.binmode
      decoded = Base64.strict_decode64(screenshot_base64)
      raise Error, "Screenshot is too large" if decoded.bytesize > MAX_SCREENSHOT_BYTES

      file.write(decoded)
      file.rewind

      upload = Multipart::Post::UploadIO.new(file, "image/png", "allure-feedback.png")
      response = self.class.post(upload_url, request_options.merge(body: { file: upload }, multipart: true))
      parsed = parse_response(response)
      return parsed if response.success? && parsed["markdown"].present?

      raise Error, gitlab_error(response, parsed)
    rescue ArgumentError
      raise Error, "Screenshot is not valid base64"
    ensure
      file&.close!
    end

    def issue_body(description:, screenshot_markdown:, reporter:, page_path:, user_agent:, viewport:)
      {
        title: title_from(description),
        description: issue_description(
          description: description,
          screenshot_markdown: screenshot_markdown,
          reporter: reporter,
          page_path: page_path,
          user_agent: user_agent,
          viewport: viewport
        ),
        labels: config.labels.join(","),
        confidential: config.confidential?
      }
    end

    def issue_description(description:, screenshot_markdown:, reporter:, page_path:, user_agent:, viewport:)
      <<~MARKDOWN
        #{description.to_s.truncate(MAX_DESCRIPTION_LENGTH)}

        #{screenshot_markdown}

        ---

        **Reporter:** #{reporter.presence || "Unknown"}
        **Page:** #{page_path.presence || "Unknown"}
        **Viewport:** #{viewport.presence || "Unknown"}
        **User agent:** #{user_agent.presence || "Unknown"}
      MARKDOWN
    end

    def title_from(description)
      first_line = description.to_s.lines.first.to_s.strip
      first_line = "Allure feedback" if first_line.blank?
      first_line.truncate(90)
    end

    def parse_response(response)
      body = response.body.to_s
      return {} if body.bytesize > MAX_RESPONSE_BYTES

      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def gitlab_error(response, parsed)
      message = parsed["message"] || parsed["error"] || "unknown error"
      "GitLab API returned #{response.code}: #{message}"
    end

    def request_options
      {
        headers: { "PRIVATE-TOKEN" => config.token },
        timeout: 30
      }
    end

    def upload_url
      "#{api_base}/projects/#{project_id}/uploads"
    end

    def issue_url
      "#{api_base}/projects/#{project_id}/issues"
    end

    def api_base
      config.api_url
    end

    def project_id
      CGI.escape(config.project_id)
    end
  end
end
