# frozen_string_literal: true

# Historical weather in specs (PLAN_WEATHER.md §10). `weather: true` turns the
# feature on against test hosts; `stub_open_meteo` answers every location
# with the same synthetic hourly values over the requested dates.
module WeatherHelpers
  FORECAST_URL = "https://forecast.weather.test"
  ARCHIVE_URL = "https://archive.weather.test"

  def open_meteo_hourly(start_date, end_date, temperature: 12.0, wind: 4.0, direction: 225.0, code: 2, precipitation: 0.0)
    first = Time.utc(start_date.year, start_date.month, start_date.day).to_i
    hours = (((end_date - start_date).to_i + 1) * 24)
    times = Array.new(hours) { |index| first + index * 3_600 }
    {
      "time" => times,
      "temperature_2m" => Array.new(hours, temperature), "apparent_temperature" => Array.new(hours, temperature && temperature - 2),
      "relative_humidity_2m" => Array.new(hours, 70.0), "precipitation" => Array.new(hours, precipitation),
      "weather_code" => Array.new(hours, code), "cloud_cover" => Array.new(hours, 40.0),
      "surface_pressure" => Array.new(hours, 1012.0), "wind_speed_10m" => Array.new(hours, wind),
      "wind_direction_10m" => Array.new(hours, direction), "wind_gusts_10m" => Array.new(hours, wind && wind * 2)
    }
  end

  def stub_open_meteo(endpoint: :forecast, status: 200, **values)
    base = endpoint == :archive ? ARCHIVE_URL : FORECAST_URL
    path = endpoint == :archive ? "/v1/archive" : "/v1/forecast"
    stub_request(:get, %r{\A#{Regexp.escape(base)}#{path}\?}).to_return do |request|
      query = Rack::Utils.parse_query(URI(request.uri).query)
      count = query.fetch("latitude").split(",").length
      hourly = open_meteo_hourly(Date.iso8601(query.fetch("start_date")), Date.iso8601(query.fetch("end_date")), **values)
      body = count == 1 ? { "hourly" => hourly } : Array.new(count) { { "hourly" => hourly } }
      { status:, body: (status == 200 ? body : { "error" => true, "reason" => "test" }).to_json,
        headers: { "Content-Type" => "application/json" } }
    end
  end

  # A positioned workout of `minutes` heading north at ~5 m/s.
  def weather_workout(user:, minutes: 90, started_at: Time.utc(2026, 5, 10, 8, 20), sport: catalog_sport("cycling"))
    workout = create(:workout, user:, sport:, started_at:, duration: minutes * 60, moving_time: minutes * 60,
                               pause_time: 0, distance: minutes * 300.0, points_count: minutes * 3 + 1)
    points = (0..(minutes * 3)).map do |index|
      { "t" => index * 20, "d" => index * 100.0, "lat" => 45.0 + index * 0.0009, "lon" => 6.0, "ele" => 300.0 }
    end
    workout.track_segments.delete_all
    create(:track_segment, workout:, position: 0, started_at:, duration: minutes * 60, moving_time: minutes * 60,
                           pause_time: 0, distance: minutes * 300.0, points:)
    workout.reload
  end
end

RSpec.configure do |config|
  config.include WeatherHelpers

  config.around(:each, :weather) do |example|
    keys = %w[WEATHER_ENABLED WEATHER_FORECAST_URL WEATHER_ARCHIVE_URL WEATHER_API_KEY WEATHER_REQUESTS_PER_SECOND]
    previous = keys.to_h { |key| [ key, ENV[key] ] }
    ENV["WEATHER_ENABLED"] = "true"
    ENV["WEATHER_FORECAST_URL"] = WeatherHelpers::FORECAST_URL
    ENV["WEATHER_ARCHIVE_URL"] = WeatherHelpers::ARCHIVE_URL
    ENV.delete("WEATHER_API_KEY")
    ENV["WEATHER_REQUESTS_PER_SECOND"] = "1000"
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
