# frozen_string_literal: true

module Allure
  module Auth
    # Authentication settings (docs/dev/AUTH.md). Read from the environment at
    # call time; a missing, non-numeric or non-positive value falls back to the
    # documented default rather than disabling the limit.
    module Config
      DEFAULT_SESSION_IDLE_DAYS = 30
      DEFAULT_SESSION_MAX_DAYS = 90
      DEFAULT_SECOND_FACTOR_GRACE_DAYS = 14
      REAUTHENTICATION_WINDOW = 10.minutes
      STEP_UP_WINDOW = 15.minutes
      LAST_SEEN_REFRESH = 5.minutes
      PENDING_SIGN_IN_LIFETIME = 5.minutes
      PENDING_SIGN_IN_ATTEMPTS = 5

      module_function

      def session_idle_timeout
        positive_days("AUTH_SESSION_IDLE_DAYS", DEFAULT_SESSION_IDLE_DAYS)
      end

      def session_max_lifetime
        positive_days("AUTH_SESSION_MAX_DAYS", DEFAULT_SESSION_MAX_DAYS)
      end

      # Zero is a valid choice here: every password account must enrol at its
      # next sign-in.
      def second_factor_grace
        value = Integer(ENV.fetch("AUTH_2FA_GRACE_DAYS", "").strip, exception: false)
        (value && value >= 0 ? value : DEFAULT_SECOND_FACTOR_GRACE_DAYS).days
      end

      # Comma-separated `TEAMID.bundle` identifiers allowed to use this
      # instance's passkeys (docs/dev/AUTH.md).
      def ios_app_ids
        ENV.fetch("IOS_APP_IDS", "").split(",").map(&:strip).grep(/\A[A-Z0-9]{10}\.[A-Za-z0-9.-]+\z/)
      end

      def reauthentication_window = REAUTHENTICATION_WINDOW

      def step_up_window = STEP_UP_WINDOW

      def pending_sign_in_lifetime = PENDING_SIGN_IN_LIFETIME

      def pending_sign_in_attempts = PENDING_SIGN_IN_ATTEMPTS

      def last_seen_refresh = LAST_SEEN_REFRESH

      def positive_days(key, default)
        value = Integer(ENV.fetch(key, "").strip, exception: false)
        (value&.positive? ? value : default).days
      end
      private_class_method :positive_days
    end
  end
end
