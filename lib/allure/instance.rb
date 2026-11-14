# frozen_string_literal: true

require "uri"

module Allure
  # Presentation metadata for this instance: its display name, an optional
  # description, and who hosts it. None of it is permanent identity — actor
  # URIs, keys, and object IDs stay in Allure::Federation::Config. Everything
  # is read from the environment at call time and stays absent when unset.
  module Instance
    DEFAULT_NAME = "Allure"
    # Where the running code's source can be read (AGPL-3.0 §13). An instance
    # running modified code points ALLURE_SOURCE_URL at its own copy.
    DEFAULT_SOURCE_URL = "https://github.com/allure-rocks/allure"

    module_function

    def name
      ENV.fetch("INSTANCE_NAME", "").strip.presence || DEFAULT_NAME
    end

    # The instance's own name in username space: transliterated to ASCII,
    # downcased, every run of characters outside the username alphabet
    # collapsed to one underscore, the ends trimmed, capped at the username
    # length. Nobody may register it (User#username_not_instance_name).
    def reserved_usernames
      candidate = ActiveSupport::Inflector.transliterate(name)
        .downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")[0, 30]
      candidate.present? ? [ candidate ] : []
    end

    def description
      ENV.fetch("INSTANCE_DESCRIPTION", "").strip.presence
    end

    def host_name
      ENV.fetch("INSTANCE_HOST_NAME", "").strip.presence
    end

    # An optional public page for the host. Only absolute http(s) URLs are
    # accepted; anything else renders as if it were unset.
    def host_url
      public_url(ENV.fetch("INSTANCE_HOST_URL", ""))
    end

    # Unset or invalid falls back to the upstream repository, so a member is
    # always offered a source.
    def source_url
      public_url(ENV.fetch("ALLURE_SOURCE_URL", "")) || DEFAULT_SOURCE_URL
    end

    def public_url(value)
      value = value.to_s.strip
      return if value.blank?

      parsed = URI.parse(value)
      valid = parsed.absolute? && parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
        parsed.userinfo.blank? && parsed.query.blank? && parsed.fragment.blank?
      valid ? value : nil
    rescue URI::InvalidURIError, URI::InvalidComponentError
      nil
    end
    private_class_method :public_url

    def hosted_by? = host_name.present?
  end
end
