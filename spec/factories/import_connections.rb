# frozen_string_literal: true

FactoryBot.define do
  factory :import_connection do
    user
    provider { "garmin_connect" }
    status { "unlinked" }

    trait :linked do
      status { "linked" }
      linked_at { Time.current }
      external_account_id { "151984342" }
      external_account_name { "Rider Garmin" }
      credentials { { "di_token" => "access", "di_refresh_token" => "refresh", "di_client_id" => "CID" } }
    end
  end
end
