# frozen_string_literal: true

require "uri"

module Allure
  module Gitlab
    class Config
      class InvalidConfiguration < StandardError; end

      DEFAULT_API_URL = "https://gitlab.com/api/v4"

      attr_reader :api_url, :project_id, :token, :labels

      def initialize(
        enabled: ENV.fetch("GITLAB_ENABLED", "false"),
        api_url: ENV.fetch("GITLAB_API_URL", DEFAULT_API_URL),
        project_id: ENV.fetch("GITLAB_PROJECT_ID", ""),
        token: ENV.fetch("GITLAB_TOKEN", ""),
        labels: ENV.fetch("GITLAB_LABELS", "feedback,allure"),
        confidential: ENV.fetch("GITLAB_CONFIDENTIAL", "false")
      )
        @enabled = boolean(enabled)
        @api_url = api_url.to_s.strip.chomp("/")
        @project_id = project_id.to_s.strip
        @token = token.to_s.strip
        @labels = normalize_labels(labels)
        @confidential = boolean(confidential)
      end

      def enabled? = @enabled
      def confidential? = @confidential
      def secure?
        URI.parse(api_url).scheme == "https"
      rescue URI::InvalidURIError
        false
      end

      def configured?
        enabled? && project_id.present? && token.present? && valid_api_url?
      end

      def validate!
        return true unless enabled?

        raise InvalidConfiguration, "GITLAB_API_URL is not a valid HTTP URL" unless valid_api_url?
        raise InvalidConfiguration, "GITLAB_PROJECT_ID is required when GitLab is enabled" if project_id.blank?
        raise InvalidConfiguration, "GITLAB_TOKEN is required when GitLab is enabled" if token.blank?

        true
      end

      private

      def boolean(value)
        ActiveModel::Type::Boolean.new.cast(value) == true
      end

      def normalize_labels(value)
        values = value.is_a?(Array) ? value : value.to_s.split(",")
        values.map { |label| label.to_s.strip }.reject(&:blank?).uniq
      end

      def valid_api_url?
        uri = URI.parse(api_url)
        uri.host.present? && %w[http https].include?(uri.scheme) &&
          uri.userinfo.blank? && uri.query.blank? && uri.fragment.blank?
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
