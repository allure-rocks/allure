# frozen_string_literal: true

module Settings
  # Account security (M4 Slice 1): password change, the paginated active-session
  # table with per-session revoke, and sign out everywhere. Destructive wording
  # follows DESIGN.md §19.12 verbatim. Closing sessions requires a recent proof
  # of identity (PLAN_AUTH.md §5.5), so a stolen cookie cannot sign its owner
  # out of their other devices.
  class SecurityController < ApplicationController
    include Pagy::Method

    allow_enrolment_only_access only: :show
    before_action :require_recent_authentication, only: %i[destroy_session destroy_all_sessions]
    # A visitor on a demo's shared account must not lock the next one out
    # (PLAN_DEMO.md §3).
    before_action :refuse_demo_account_lockout, only: :update_password

    SESSIONS_PER_PAGE = 10
    # Sort keys are URL state (DESIGN.md §10.5, §13): one `field_direction`
    # value, whitelisted so a crafted URL never reaches SQL.
    SESSION_SORTS = {
      "device_asc" => { user_agent: :asc },
      "device_desc" => { user_agent: :desc },
      "last_seen_asc" => { last_seen_at: :asc },
      "last_seen_desc" => { last_seen_at: :desc }
    }.freeze
    DEFAULT_SESSION_SORT = "last_seen_desc"

    def show
      @user = current_user
      load_sessions
    end

    # The second-factor reminder (PLAN_AUTH.md §5.3) stays hidden for the rest
    # of the day.
    def dismiss_reminder
      cookies[:second_factor_reminder_dismissed] = { value: Date.current.iso8601, expires: Time.current.end_of_day,
                                                     httponly: true, same_site: :lax }
      redirect_back_or_to settings_security_path, status: :see_other
    end

    # A password-less account adds its first password after re-authenticating
    # (PLAN_AUTH.md §5.6); the second-factor grace period starts with it.
    def update_password
      @user = current_user
      adding = !@user.password?
      return require_recent_authentication if adding && !Current.session.recently_authenticated?

      load_sessions

      unless adding || @user.authenticate(password_params[:current_password])
        @user.errors.add(:current_password, :invalid)
        render :show, status: :unprocessable_content
        return
      end

      attributes = password_params.slice(:password, :password_confirmation)
      if attributes[:password].blank?
        @user.errors.add(:password, :blank)
        render :show, status: :unprocessable_content
      elsif @user.update(attributes)
        SecurityMailer.notice(@user, "password_added").deliver_later if adding
        # Other sessions only: the current one stays alive so the user is not
        # kicked out mid-flow.
        @user.sessions.where.not(id: Current.session.id).destroy_all
        # The current password was just proved again.
        Current.session.reauthenticate!
        redirect_to settings_security_path, notice: t(adding ? "settings.security.password.added" : "settings.security.password.success")
      else
        render :show, status: :unprocessable_content
      end
    end

    def destroy_session
      session = current_user.sessions.find(params[:id])
      if session == Current.session
        redirect_to settings_security_path(session_list_params), alert: t("settings.security.sessions.current_revoke")
      else
        session.destroy!
        redirect_to settings_security_path(session_list_params), notice: t("settings.security.sessions.revoked")
      end
    end

    def destroy_all_sessions
      current_user.sessions.destroy_all
      drop_session_cookie
      redirect_to new_session_path, notice: t("settings.security.sessions.all_revoked")
    end

    private

    def load_sessions
      @policy = Auth::SecondFactorPolicy.new(current_user)
      @passkeys = current_user.webauthn_credentials.order(:created_at)
      @recovery_codes_left = current_user.recovery_codes.unused.count
      @identities = current_user.identities.order(:linked_at)
      linked = @identities.map(&:provider)
      @linkable_providers = Allure::Auth::Providers.enabled.reject { |provider| linked.include?(provider.name) }
      @session_sort = SESSION_SORTS.key?(params[:sort].to_s) ? params[:sort].to_s : DEFAULT_SESSION_SORT
      @pagy, @sessions = pagy(
        current_user.sessions.order(SESSION_SORTS.fetch(@session_sort)).order(id: :desc),
        limit: SESSIONS_PER_PAGE
      )
    end

    # The table is URL state: page and sort survive a revoke so the list does
    # not jump back to its first page.
    def session_list_params
      params.permit(:page, :sort).to_h.compact_blank
    end

    def password_params
      params.require(:user).permit(:current_password, :password, :password_confirmation)
    end
  end
end
