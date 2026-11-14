# frozen_string_literal: true

require Rails.root.join("lib/allure/federation").to_s
require Rails.root.join("lib/allure/federation/media_types").to_s

Mime::Type.register(Allure::Federation::MediaTypes::ACTIVITY_PUB, :activity_json)
Mime::Type.register(Allure::Federation::MediaTypes::WEBFINGER, :webfinger)
Mime::Type.register(Allure::Federation::MediaTypes::GPX, :gpx)
