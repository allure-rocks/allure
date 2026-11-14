# frozen_string_literal: true

module Auth
  # Whether an account owes a second factor (PLAN_AUTH.md §5.3):
  #
  # - `:satisfied` — enrolled, or nothing owed (an account without a password);
  # - `:grace` — owed, before the deadline;
  # - `:required` — owed, deadline passed: password sign-in leads to enrolment.
  #
  # The operator has no grace period.
  class SecondFactorPolicy
    attr_reader :user, :now

    STATES = %w[satisfied grace required].freeze

    # Accounts per state, for the metrics exporter (PLAN_AUTH.md §11). The
    # same rules as #state, in SQL.
    def self.counts(now: Time.current)
      # A demo instance owes nothing (PLAN_DEMO.md §3).
      return { "satisfied" => User.count, "grace" => 0, "required" => 0 } if Allure::Demo.enabled?

      enrolled = User.where.not(otp_enrolled_at: nil).or(User.where(id: WebauthnCredential.select(:user_id)))
      owed = User.where.not(id: enrolled.select(:id)).where.not(second_factor_required_since: nil)
      required = owed.where("second_factor_required_since <= :cut OR username = :operator",
                            cut: now - Allure::Auth::Config.second_factor_grace,
                            operator: User.operator_username.presence || "").count
      grace = owed.count - required
      { "satisfied" => User.count - required - grace, "grace" => grace, "required" => required }
    end

    def initialize(user, now: Time.current)
      @user = user
      @now = now
    end

    def state
      @state ||=
        # A demo instance owes nothing (PLAN_DEMO.md §3): its shared accounts
        # sign in with a password alone, the operator included.
        if Allure::Demo.enabled?
          :satisfied
        elsif user.second_factor_enrolled? || deadline.nil?
          :satisfied
        elsif now < deadline
          :grace
        else
          :required
        end
    end

    def satisfied? = state == :satisfied
    def grace? = state == :grace
    def required? = state == :required

    def deadline
      return @deadline if defined?(@deadline)

      since = user.second_factor_required_since
      since ||= user.created_at if user.instance_operator?
      @deadline = since && (since + (user.instance_operator? ? 0.days : Allure::Auth::Config.second_factor_grace))
    end

    # Whole days left, counting today, for the reminder.
    def days_left
      return 0 unless grace?

      ((deadline - now) / 1.day).ceil
    end
  end
end
