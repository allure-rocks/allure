# frozen_string_literal: true

require "base64"
require "uri"

class FeedbackController < ApplicationController
  MAX_DESCRIPTION_LENGTH = 10_000
  MAX_SCREENSHOT_BYTES = 8.megabytes
  DATA_URI_PREFIX = %r{\Adata:image/png;base64,}i

  def create
    config = Allure::Gitlab.config
    unless config.enabled?
      render_error("feedback.errors.disabled", :forbidden)
      return
    end

    unless config.configured?
      render_error("feedback.errors.not_configured", :unprocessable_content)
      return
    end

    description = params[:description].to_s.strip
    if description.blank?
      render_error("feedback.errors.description_required", :unprocessable_content)
      return
    end

    if description.length > MAX_DESCRIPTION_LENGTH
      render_error("feedback.errors.description_too_long", :unprocessable_content)
      return
    end

    screenshot_base64 = extract_screenshot(params[:screenshot].to_s)
    return unless screenshot_base64

    issue_url = Feedback::GitlabIssueService.new.create_issue!(
      description: description,
      screenshot_base64: screenshot_base64,
      reporter: current_user&.email_address,
      page_path: sanitized_page_path(params[:pagePath] || params[:page_path]),
      user_agent: bounded_string(params[:userAgent] || params[:user_agent], 512).presence || request.user_agent,
      viewport: bounded_string(params[:viewport], 64)
    )

    render json: { issueUrl: issue_url }
  rescue Feedback::GitlabIssueService::Error => e
    Rails.logger.warn "Feedback GitLab issue creation failed: #{e.message}"
    render_error("feedback.errors.creation_failed", :bad_gateway)
  end

  private

  def render_error(key, status)
    render json: { errors: [ t(key) ] }, status:
  end

  def extract_screenshot(value)
    unless value.match?(DATA_URI_PREFIX)
      render_error("feedback.errors.screenshot_data_uri", :unprocessable_content)
      return nil
    end

    base64 = value.sub(DATA_URI_PREFIX, "")
    decoded = Base64.strict_decode64(base64)

    unless decoded.start_with?("\x89PNG\r\n\x1A\n".b)
      render_error("feedback.errors.screenshot_png", :unprocessable_content)
      return nil
    end

    if decoded.bytesize > MAX_SCREENSHOT_BYTES
      render_error("feedback.errors.screenshot_too_large", :payload_too_large)
      return nil
    end

    base64
  rescue ArgumentError
    render_error("feedback.errors.screenshot_base64", :unprocessable_content)
    nil
  end

  def sanitized_page_path(value)
    value = bounded_string(value, 2048)
    return nil if value.blank?

    uri = URI.parse(value)
    if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      uri.path.presence || "/"
    elsif uri.host.blank? && uri.path.start_with?("/") && !uri.path.start_with?("//")
      uri.path
    end
  rescue URI::InvalidURIError
    nil
  end

  def bounded_string(value, length)
    value.to_s.strip.truncate(length, omission: "")
  end
end
