# frozen_string_literal: true

module ImportConnections
  # « Récupérer des activités » (PLAN_REMOTE_IMPORTS.md §8.2): one manual
  # batch over a date range, listed and imported by the remote batch job.
  class Retrieval
    Result = Data.define(:batch, :error) do
      def success? = error.nil?
    end

    def initialize(connection:, from:, to:, sport: nil, today: Date.current)
      @connection = connection
      @from = parse(from)
      @to = parse(to)
      @sport = sport
      @today = today
    end

    def call
      return failure("not_linked") unless @connection.usable?
      return failure("invalid_range") if @from.nil? || @to.nil? || @from > @to || @to > @today

      batch = @connection.user.workout_import_batches.create!(
        source: @connection.provider, import_connection: @connection, trigger: "manual",
        range_from: @from, range_to: @to, sport: @sport
      )
      Workouts::RemoteImportBatchJob.perform_later(batch)
      Result.new(batch:, error: nil)
    end

    private

    def failure(key) = Result.new(batch: nil, error: I18n.t("settings.connections.retrieval.errors.#{key}"))

    def parse(value)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
