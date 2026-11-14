# frozen_string_literal: true

module AllureMcp
  # `allure_mcp_requests_total` (PLAN_METRICS.md): one count per JSON-RPC
  # request. Labels stay bounded — a tool name a client invents is `unknown`.
  module Metrics
    METHODS = %w[initialize ping tools/list tools/call].freeze
    OUTCOMES = %w[ok not_found invalid error].freeze
    ARGUMENT_ERRORS = %i[missing_required_arguments invalid_schema tool_not_found].freeze

    module_function

    def record(data, context)
      method = METHODS.include?(data[:method].to_s) ? data[:method].to_s : "other"
      tool = tool_label(method, data[:tool_name])
      Yabeda.allure.mcp_requests_total.increment({ method:, tool:, outcome: outcome(data, context, method) })
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: "mcp_requests_total" })
    end

    def tool_label(method, name)
      return "none" unless method == "tools/call"

      Server::TOOLS.map(&:name_value).include?(name.to_s) ? name.to_s : "unknown"
    end

    def outcome(data, context, method)
      if data[:error]
        ARGUMENT_ERRORS.include?(data[:error]) ? "invalid" : "error"
      elsif method == "tools/call"
        OUTCOMES.include?(context.outcome) ? context.outcome : "error"
      else
        "ok"
      end
    end
  end
end
