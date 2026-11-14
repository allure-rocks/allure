# frozen_string_literal: true

module Federation
  # The single remote-content sanitizer (PLAN_M5 §12.4): an explicit allowlist
  # for what a received note may render. Applied at parse time and again at
  # render time; links may only use http(s).
  module RemoteText
    ALLOWED_TAGS = %w[p br strong em b i ul ol li a blockquote].freeze
    ALLOWED_ATTRIBUTES = %w[href].freeze
    ALLOWED_PROTOCOLS = %w[http https].freeze

    module_function

    def sanitize(value)
      return if value.nil?

      sanitizer.sanitize(
        value.to_s,
        tags: ALLOWED_TAGS,
        attributes: ALLOWED_ATTRIBUTES,
        protocols: ALLOWED_PROTOCOLS
      )
    end

    # Plain-text projection used for the description field. Block boundaries
    # become spaces so adjacent lines do not run together.
    def text(value)
      sanitized = sanitize(value)
      return if sanitized.nil?

      spaced = sanitized
        .gsub(%r{<br\s*/?>}i, " ")
        .gsub(%r{</(?:p|li|blockquote)>}i, " ")
      ActionController::Base.helpers.strip_tags(spaced).squish.presence
    end

    def sanitizer
      @sanitizer ||= Rails::HTML5::SafeListSanitizer.new
    end
  end
end
