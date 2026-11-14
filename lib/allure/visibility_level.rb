# frozen_string_literal: true

module Allure
  module VisibilityLevel
    LEVELS = %w[public followers_only private].freeze
    RANKS = LEVELS.each_with_index.to_h.freeze

    module_function

    def rank(level)
      RANKS.fetch(level.to_s) { raise ArgumentError, "unknown visibility level: #{level.inspect}" }
    end

    def cap(requested, parent)
      LEVELS.fetch([ rank(requested), rank(parent) ].max)
    end
  end
end
