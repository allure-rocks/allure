# frozen_string_literal: true

require "base64"

module Allure
  module GarminConnect
    # The headers the Garmin Connect Android application sends to diauth and
    # connectapi (python-garminconnect 0.3.11 `_native_headers`).
    module NativeHeaders
      USER_AGENT = "GCM-Android-5.23"
      X_GARMIN_USER_AGENT = "com.garmin.android.apps.connectmobile/5.23; ; " \
                            "Google/sdk_gphone64_arm64/google; Android/33; Dalvik/2.1.0"
      APP_VERSION = "10861"

      BASE = {
        "User-Agent" => USER_AGENT,
        "X-Garmin-User-Agent" => X_GARMIN_USER_AGENT,
        "X-Garmin-Paired-App-Version" => APP_VERSION,
        "X-Garmin-Client-Platform" => "Android",
        "X-App-Ver" => APP_VERSION,
        "X-Lang" => "en",
        "X-GCExperience" => "GC5",
        "Accept-Language" => "en-US,en;q=0.9"
      }.freeze

      def self.call(extra = {})
        BASE.merge(extra)
      end

      def self.basic_auth(client_id)
        "Basic #{Base64.strict_encode64("#{client_id}:")}"
      end
    end
  end
end
