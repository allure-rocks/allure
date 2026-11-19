# frozen_string_literal: true

module AllureMcp
  module Tools
    # What every Allure tool shares (docs/dev/MCP.md): the token's account as
    # the only scope, owner lookups that answer "not found" for anything else,
    # compact JSON text answers, and the outcome reported to the metrics.
    class Base < MCP::Tool
      class NotFound < StandardError; end
      class InvalidArgument < StandardError; end

      FLOAT_DECIMALS = 5
      READ_ONLY = { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }.freeze

      class << self
        def call(server_context:, **arguments)
          payload = rounded(perform(server_context, **arguments))
          server_context.outcome = "ok"
          MCP::Tool::Response.new([ { type: "text", text: JSON.generate(payload) } ])
        rescue NotFound => error
          failure(server_context, "not_found", error.message)
        rescue InvalidArgument => error
          failure(server_context, "invalid", error.message)
        end

        private

        def perform(_context, **)
          raise NotImplementedError
        end

        # Float noise such as 262.2999999999993 costs a model tokens and
        # nothing else; five decimals keep a coordinate within a metre.
        def rounded(value)
          case value
          when Float then value.round(FLOAT_DECIMALS)
          when Hash then value.transform_values { rounded(it) }
          when Array then value.map { rounded(it) }
          else value
          end
        end

        def failure(context, outcome, message)
          context.outcome = outcome
          MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
        end

        def owned_workout(context, id, includes: nil)
          uuid = Allure::ShortId.decode(id.to_s)
          scope = context.user.workouts
          scope = scope.includes(includes) if includes
          scope.find_by(uuid:) || raise(NotFound, missing_workout(id))
        rescue ArgumentError
          raise NotFound, missing_workout(id)
        end

        def missing_workout(id) = "No workout #{id.to_s.truncate(40).inspect} on this account. Use list_workouts to find an id."
      end
    end
  end
end
