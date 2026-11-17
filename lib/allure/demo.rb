# frozen_string_literal: true

module Allure
  # The demo mode (docs/dev/DEMO.md): a throwaway public instance whose database is
  # recreated from the development seed every night, and whose shared accounts'
  # credentials are published on the sign-in page. The switch is read from
  # DEMO_INSTANCE and changes three things, nothing else:
  #
  # 1. no second factor is owed by anyone (docs/dev/AUTH.md's demo exception),
  #    and the operator console's step-up accepts a recent password proof;
  # 2. the accounts named by DEMO_ACCOUNTS are shared playgrounds: no visitor
  #    may lock the next one out by changing a password, enrolling a factor or
  #    requesting the account's deletion;
  # 3. no session IP address is ever persisted, since every surface that shows
  #    one would show it to strangers.
  module Demo
    class InvalidConfiguration < StandardError; end

    # How long before the nightly reset the site-wide strip turns into an
    # urgent warning, without any reload.
    RESET_WARNING_WINDOW = 5.minutes

    module_function

    def enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("DEMO_INSTANCE", "false")) == true
    end

    # The usernames whose credentials are published on the sign-in page.
    def accounts
      usernames = ENV.fetch("DEMO_ACCOUNTS", "").split(",").map { |name| name.strip.downcase }.reject(&:blank?).uniq
      if enabled? && operator_username.present? && usernames.include?(operator_username)
        raise InvalidConfiguration, "DEMO_ACCOUNTS must not include INSTANCE_OPERATOR_USERNAME (#{operator_username})"
      end

      usernames
    end

    def shared_account?(user)
      return false unless enabled? && user

      accounts.include?(user.username)
    end

    # The single account allowed into /admin, normalized like
    # User.operator_username. The demo seeds it with #operator_password.
    def operator_username
      ENV.fetch("INSTANCE_OPERATOR_USERNAME", "").strip.downcase
    end

    # The operator's stable password on a demo (docs/dev/DEMO.md): the seed
    # assigns it on every pass, so the console survives the nightly reset and
    # the credential never appears on the sign-in page. Nil when the console is
    # closed (no operator configured).
    def operator_password
      ENV.fetch("DEMO_OPERATOR_PASSWORD", "").presence
    end

    # Refuse a demo configuration that cannot authenticate its operator before
    # any server, worker or seed starts. #accounts keeps the shared-account
    # check on every read, so a seed or credential rendering cannot expose the
    # operator if the configuration changes after boot.
    def validate!
      return unless enabled?

      accounts
      return if operator_username.blank?

      password = operator_password
      if password.blank?
        raise InvalidConfiguration,
              "DEMO_OPERATOR_PASSWORD is required when INSTANCE_OPERATOR_USERNAME is set"
      end
      if password.length < User::MINIMUM_PASSWORD_LENGTH
        raise InvalidConfiguration,
              "DEMO_OPERATOR_PASSWORD must be at least #{User::MINIMUM_PASSWORD_LENGTH} characters"
      end
      if ENV.fetch("DEMO_PASSWORD", "").present? && password == ENV.fetch("DEMO_PASSWORD")
        raise InvalidConfiguration, "DEMO_OPERATOR_PASSWORD must differ from DEMO_PASSWORD"
      end
    end

    # The next occurrence of the nightly reset, `HH:MM` (DEMO_RESET_AT) in the
    # container's TZ. The host-side reset script reads the same two variables,
    # so the schedule exists in exactly one place.
    def reset_at(now = Time.current)
      zone = Time.find_zone(ENV.fetch("TZ", "")) || Time.zone
      hour, minute = ENV.fetch("DEMO_RESET_AT", "03:00").split(":", 2)
      # Anchored on the caller's own day, in the demo zone.
      scheduled = now.in_time_zone(zone).change(hour: hour.to_i, min: minute.to_i, sec: 0)
      scheduled > now ? scheduled : scheduled + 1.day
    end
  end
end
