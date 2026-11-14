module Authentication
  extend ActiveSupport::Concern

  # The browser-session state of an unfinished authentication step. It
  # belongs to whoever was using the browser, so it goes whenever an account
  # signs in or a session ends (PLAN_AUTH.md §8): a secret, recovery codes or
  # a provider identity must never pass to the next person.
  # `return_to_after_authenticating` is not here: it is the next person's own.
  AUTHENTICATION_FLOW_KEYS = %i[
    pending_sign_in pending_identity pending_otp_secret fresh_recovery_codes
    webauthn_authentication_challenge webauthn_reauthentication_challenge webauthn_registration_challenge
    companion_handoff return_to_after_reauthenticating fresh_api_token fresh_webhook_secret
  ].freeze

  included do
    before_action :require_authentication
    before_action :enforce_second_factor_enrolment
    before_action :enforce_deletion_window
    helper_method :authenticated?, :enrolment_only_session?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :enforce_second_factor_enrolment, **options
      skip_before_action :enforce_deletion_window, **options
    end

    # The pages an enrolment-only session may reach (PLAN_AUTH.md §5.3).
    def allow_enrolment_only_access(**options)
      skip_before_action :enforce_second_factor_enrolment, **options
    end

    # The pages an account in its deletion window may reach
    # (PLAN_ACCOUNT.md §4.2).
    def allow_deletion_window_access(**options)
      skip_before_action :enforce_deletion_window, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      return unless cookies.signed[:session_id] && (session = Session.find_by(id: cookies.signed[:session_id]))

      # A suspended account, an account whose purge has started, or an
      # expired session is signed out server-side: the row is revoked and the
      # cookie dropped, so an old browser loses access on its next request.
      if session.user&.suspended? || session.user&.deletion_started? || session.expired?
        session.destroy
        drop_session_cookie
        return
      end

      # An enrolment-only session whose account gained a factor elsewhere only
      # ever proved the password: it ends, and the next sign-in asks for the
      # factor instead of leaving it on the enrolment page (PLAN_AUTH.md §5.3).
      if session.enrolment_only? && session.user.second_factor_enrolled?
        session.destroy
        drop_session_cookie
        flash[:notice] = t("second_factor.signed_out_after_enrolment")
        return
      end

      session.record_activity!
      session
    end

    def enrolment_only_session? = Current.session&.enrolment_only? || false

    # A password account whose grace period has ended may only enrol a second
    # factor (PLAN_AUTH.md §5.3). A full session whose deadline passes while it
    # is open becomes enrolment-only on its next request.
    def enforce_second_factor_enrolment
      current = Current.session
      return unless current

      if !current.enrolment_only? && current.second_factor_at.nil? &&
         allure_factor_applies?(current.user, current.auth_method) && Auth::SecondFactorPolicy.new(current.user).required?
        current.update!(enrolment_only: true)
      end
      return unless current.enrolment_only?

      if request.headers["Turbo-Frame"].present?
        head :no_content
      else
        # The security page's card states the obligation; no flash repeats it.
        redirect_to settings_security_path, status: :see_other
      end
    end

    # An account whose deletion is scheduled is deactivated: every page leads
    # to the one that offers to cancel it (PLAN_ACCOUNT.md §4.2).
    def enforce_deletion_window
      return unless Current.session&.user&.deletion_scheduled?

      if request.headers["Turbo-Frame"].present? || !request.format.html?
        head :no_content
      else
        redirect_to settings_account_deletion_path, status: :see_other
      end
    end

    # Sensitive actions need a recent proof of identity (PLAN_AUTH.md §5.5).
    # A GET returns to itself afterwards; any other request returns to the page
    # it was sent from, where the person repeats the action.
    def require_recent_authentication
      return if Current.session.recently_authenticated?

      redirect_to_reauthentication
    end

    # The operator console re-confirms a second factor (PLAN_AUTH.md §5.4). A
    # demo operator holds no factor at all (PLAN_DEMO.md §3): the console still
    # needs a recent proof of identity, and the password is the only one left.
    def require_recent_second_factor
      return if Current.session.recent_second_factor?
      return if Allure::Demo.enabled? && Current.session.recently_authenticated?

      redirect_to_reauthentication
    end

    def redirect_to_reauthentication
      session[:return_to_after_reauthenticating] =
        request.get? || request.head? ? request.fullpath : url_from(request.referer)
      redirect_to new_reauthentication_path, status: :see_other
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || me_url
    end

    # The password or the provider was right (PLAN_AUTH.md §5.1, §6.2). A
    # provider's own sign-in is trusted, except for the operator. An account
    # that owes a factor and has one answers it before any session exists;
    # one that owes it without having it signs in restricted to enrolment once
    # its grace period has ended. `authenticated_at` is the moment a provider
    # reports it authenticated the person, when it reports one (§6.2).
    def begin_sign_in(user, auth_method: "password", notice: nil, authenticated_at: nil)
      if allure_factor_applies?(user, auth_method) && user.second_factor_enrolled?
        session[:pending_sign_in] = {
          "user_id" => user.id,
          "fingerprint" => pending_sign_in_fingerprint(user),
          "expires_at" => Allure::Auth::Config.pending_sign_in_lifetime.from_now.to_i,
          "attempts" => 0,
          "auth_method" => auth_method
        }
        redirect_to new_session_challenge_path
      else
        complete_sign_in(user, auth_method:, notice:, authenticated_at:)
      end
    end

    def complete_sign_in(user, second_factor: nil, auth_method: "password", notice: nil, authenticated_at: nil)
      session.delete(:pending_sign_in)
      required = second_factor.nil? && allure_factor_applies?(user, auth_method) &&
        Auth::SecondFactorPolicy.new(user).required?
      start_new_session_for(user, second_factor:, enrolment_only: required, auth_method:, authenticated_at:)
      if required
        redirect_to settings_security_path
      else
        redirect_to after_authentication_url, notice:
      end
    end

    # The account waiting for its second factor, or nil once the pending state
    # has expired, been used up, or been invalidated by a password change.
    def pending_sign_in_user
      pending = session[:pending_sign_in]
      return unless pending.is_a?(Hash) && pending["expires_at"].to_i > Time.current.to_i

      user = User.find_by(id: pending["user_id"])
      return unless user && !user.suspended? && pending["fingerprint"] == pending_sign_in_fingerprint(user)

      user
    end

    def pending_sign_in_auth_method
      method = session.dig(:pending_sign_in, "auth_method")
      Session::AUTH_METHODS.include?(method) ? method : "password"
    end

    # Allure's own second factor is owed on the password path, and by the
    # operator whatever the path (PLAN_AUTH.md §1).
    def allure_factor_applies?(user, auth_method)
      auth_method == "password" || user.instance_operator?
    end

    def pending_sign_in_fingerprint(user)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key("allure/pending-sign-in", 32),
                              "#{user.id}:#{user.password_digest}")
    end

    # The proof of identity the session starts with is the moment the person
    # authenticated: now for a password or a factor just answered, the
    # provider's own `auth_time` when it reports one (PLAN_AUTH.md §6.2).
    # The CSRF token is rotated too, so a token read before the sign-in is
    # worth nothing after it (§8).
    def start_new_session_for(user, second_factor: nil, enrolment_only: false, auth_method: "password",
                              authenticated_at: nil)
      clear_authentication_flow
      reset_csrf_token(request)
      now = Time.current
      user.sessions.create!(
        # A demo's shared accounts show their session list to strangers: no
        # IP is ever persisted there (PLAN_DEMO.md §3).
        user_agent: request.user_agent, ip_address: (Allure::Demo.enabled? ? nil : request.remote_ip),
        last_seen_at: now,
        reauthenticated_at: authenticated_at || now,
        auth_method:,
        second_factor_method: second_factor&.to_s, second_factor_at: (now if second_factor), enrolment_only:
      ).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = { value: session.id, expires: session.expires_at, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      drop_session_cookie
    end

    # Every way a browser stops being signed in: sign-out, closing every
    # session, and the server-side ends of find_session_by_cookie.
    def drop_session_cookie
      cookies.delete(:session_id)
      clear_authentication_flow
    end

    def clear_authentication_flow
      AUTHENTICATION_FLOW_KEYS.each { |key| session.delete(key) }
    end

    # Recovery codes wait for their one-time page bound to the account that
    # generated them, so no other account can ever be shown them.
    def hold_fresh_recovery_codes(codes)
      session[:fresh_recovery_codes] = { "user_id" => current_user.id, "codes" => codes }
    end

    def take_fresh_recovery_codes
      held = session.delete(:fresh_recovery_codes)
      held["codes"] if held.is_a?(Hash) && held["user_id"] == current_user&.id
    end
end
