# frozen_string_literal: true

module Allure
  module Federation
    module MediaTypes
      ACTIVITY_PUB = "application/activity+json"
      ACTIVITY_PUB_ALTERNATIVES = [
        "application/ld+json",
        'application/ld+json; profile="https://www.w3.org/ns/activitystreams"',
        "application/json"
      ].freeze

      WEBFINGER = "application/jrd+json"
      WEBFINGER_ALTERNATIVES = [ "application/json" ].freeze

      NODE_INFO = "application/json"

      GPX = "application/xml+gpx"
      GPX_ALTERNATIVES = [ "application/gpx+xml" ].freeze

      ACTIVITY_PUB_ACCEPTED = [ ACTIVITY_PUB, *ACTIVITY_PUB_ALTERNATIVES ].freeze
      WEBFINGER_ACCEPTED = [ WEBFINGER, *WEBFINGER_ALTERNATIVES ].freeze
      GPX_ACCEPTED = [ GPX, *GPX_ALTERNATIVES ].freeze
    end
  end
end
