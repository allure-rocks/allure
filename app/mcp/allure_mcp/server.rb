# frozen_string_literal: true

module AllureMcp
  # Builds the MCP server for one request (docs/dev/MCP.md). A fresh server per
  # request carries the request's principal and needs no shared state.
  module Server
    TOOLS = [
      Tools::GetWorkoutContext,
      Tools::ListWorkouts,
      Tools::GetWorkoutSeries
    ].freeze

    INSTRUCTIONS = <<~TEXT
      Allure is a sport-tracking application. These tools read the signed-in
      athlete's own workouts so you can analyse them.

      Start with list_workouts to find a workout (newest first, filterable by
      sport, dates, place or text), then call get_workout_context with its id
      for the full picture: metrics, data-quality findings, laps, climbs,
      intervals, splits, best efforts, segment efforts and the last weeks of
      training. Use get_workout_series to look at heart rate, speed, power,
      cadence or elevation over a distance or time range.

      Every value is in SI units (metres, seconds, metres per second) unless
      its name says otherwise; `units` in each answer lists them. Timestamps
      are UTC; the athlete's time zone and preferred unit system are given so
      you can present local times and metric or imperial figures. A null or
      absent measurement was not recorded; it is not zero. When `contested_metrics`
      names a figure, the recording was faulty there: prefer its
      `plausible_values` entry and say so.
    TEXT

    module_function

    def build(context)
      configuration = MCP::Configuration.new(
        exception_reporter: ->(error, _server_context) { Rails.error.report(error, handled: true, context: { component: "mcp" }) },
        instrumentation_callback: ->(data) { Metrics.record(data, context) }
      )
      MCP::Server.new(
        name: "allure",
        title: "Allure",
        version: Allure::VERSION,
        website_url: Allure::Federation.config.base_url,
        instructions: INSTRUCTIONS,
        tools: TOOLS,
        capabilities: { tools: {} },
        server_context: context,
        configuration:
      )
    end
  end
end
