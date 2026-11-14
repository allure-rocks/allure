# frozen_string_literal: true

FactoryBot.define do
  factory :workout_weather do
    workout
    status { "ready" }
    fetch_version { Workouts::WeatherEnricher::FETCH_VERSION }
    analysis_version { Workouts::WeatherEnricher::ANALYSIS_VERSION }
    endpoint { "forecast" }
    summary do
      {
        "condition" => "partly_cloudy", "temperature_min" => 11.2, "temperature_max" => 15.8, "temperature_mean" => 13.4,
        "apparent_temperature" => 10.4, "humidity" => 68, "precipitation" => 0.4, "wind_speed" => 4.2,
        "wind_gusts" => 9.1, "wind_direction" => 225,
        "wind_exposure" => { "head" => 0.42, "tail" => 0.31, "cross" => 0.27, "headwind" => 0.8 },
        "is_day" => true
      }
    end
    exposure { { "distance" => 250.0, "head" => 0.42, "tail" => 0.31, "cross" => 0.27, "headwind" => 0.8 } }
    series do
      [
        { "t" => workout.started_at.to_i, "temp" => 11.2, "feels" => 10.0, "rh" => 70, "precip" => 0.0, "code" => 2,
          "cloud" => 40, "pres" => 1012.0, "wind" => 4.0, "dir" => 220, "gust" => 8.5, "day" => true },
        { "t" => workout.started_at.to_i + 3_600, "temp" => 15.8, "feels" => 14.9, "rh" => 66, "precip" => 0.4,
          "code" => 61, "cloud" => 80, "pres" => 1011.0, "wind" => 4.4, "dir" => 230, "gust" => 9.1, "day" => true }
      ]
    end
    requests_count { 1 }
    fetched_at { Time.current }
  end
end
