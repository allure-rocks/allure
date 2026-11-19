# frozen_string_literal: true

FactoryBot.define do
  factory :workout_summary do
    workout
    locale { "fr" }
    status { "pending" }
    version { Allure::Insights::VERSION }

    trait :ready do
      status { "ready" }
      facts_digest { "d" * 64 }
      title { "Le tour du lac" }
      sentences do
        [ { "text" => "Vous avez parcouru 62,4 km avec 850 m de dénivelé.",
            "fact_ids" => %w[baseline:distance baseline:ascent] } ]
      end
      model { "qwen" }
      requests_count { 1 }
      generated_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      last_error { "unavailable" }
      requests_count { 1 }
    end
  end
end
