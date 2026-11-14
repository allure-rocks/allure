# frozen_string_literal: true

module Api
  module Rest
    module V1
      # Value formats shared by every representation (PLAN_API.md §5): RFC 3339
      # UTC instants and plain JSON numbers.
      module Formats
        module_function

        def time(value) = value&.utc&.iso8601

        def number(value)
          return if value.nil?

          float = value.to_f
          float == float.round ? float.round : float
        end
      end
    end
  end
end
