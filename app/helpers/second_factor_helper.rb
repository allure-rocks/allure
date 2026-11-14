# frozen_string_literal: true

module SecondFactorHelper
  # The grace-period reminder (PLAN_AUTH.md §5.3): the policy while the
  # account owes a second factor and has not hidden the reminder today. The
  # security page states the obligation itself.
  def second_factor_reminder
    return unless signed_in? && !enrolment_only_session?
    return if controller_path.start_with?("settings/security", "settings/totps", "settings/recovery_codes")
    return if cookies[:second_factor_reminder_dismissed] == Date.current.iso8601

    policy = Auth::SecondFactorPolicy.new(current_user)
    policy if policy.grace?
  end

  # How an account signs in, for the operator's account page (PLAN_AUTH.md §6).
  def admin_sign_in_methods(account)
    methods = []
    methods << t("admin.accounts.password_method") if account.password?
    methods.concat(account.identities.map(&:label))
    methods.to_sentence
  end

  # One line for the operator's account page (PLAN_AUTH.md §5.7).
  def admin_second_factor_state(account, policy)
    case policy.state
    when :satisfied
      methods = []
      methods << t("admin.accounts.second_factor_methods.totp") if account.totp_enrolled?
      count = account.webauthn_credentials.count
      methods << t("admin.accounts.second_factor_methods.passkeys", count:) if count.positive?
      methods.any? ? t("admin.accounts.second_factor_states.enrolled", methods: methods.to_sentence) :
        t("admin.accounts.second_factor_states.not_owed")
    when :grace
      t("admin.accounts.second_factor_states.grace", date: l(policy.deadline.to_date, format: :day_month_year))
    else
      t("admin.accounts.second_factor_states.required")
    end
  end
end
