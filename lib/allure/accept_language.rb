# frozen_string_literal: true

module Allure
  # Picks the best offered locale from an HTTP Accept-Language header
  # (RFC 9110 §12.5.4). Only the primary subtag is compared, so `de-CH` and
  # `es-419` reach `de` and `es`; a range weighted `q=0` and the `*` wildcard
  # never choose. A header longer than MAX_BYTES or MAX_RANGES is read up to
  # those bounds and the rest ignored.
  module AcceptLanguage
    MAX_BYTES = 4096
    MAX_RANGES = 64
    RANGE = /\A([a-z]{1,8})(?:-[a-z0-9]{1,8})*\z/

    module_function

    # Returns the offered locale (a String) the header prefers, or nil.
    def best_match(header, available:)
      offered = available.map(&:to_s)
      ranges(header).each do |language|
        return language if offered.include?(language)
      end
      nil
    end

    # Primary subtags in preference order: higher weight first, then the
    # header's own order.
    def ranges(header)
      entries = header.to_s.byteslice(0, MAX_BYTES).to_s.scrub("").split(",").first(MAX_RANGES)
      weighted = entries.each_with_index.filter_map do |entry, index|
        tag, *parameters = entry.split(";").map(&:strip)
        match = RANGE.match(tag.to_s.downcase)
        next unless match

        weight = weight(parameters)
        next unless weight&.positive?

        [ match[1], weight, index ]
      end
      weighted.sort_by { |_, weight, index| [ -weight, index ] }.map(&:first).uniq
    end

    def weight(parameters)
      quality = parameters.find { it.downcase.start_with?("q=") }
      return 1.0 unless quality

      value = quality.split("=", 2).last.strip
      value.match?(/\A(?:0(?:\.\d{0,3})?|1(?:\.0{0,3})?)\z/) ? value.to_f : nil
    end
  end
end
