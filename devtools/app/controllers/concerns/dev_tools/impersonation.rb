# frozen_string_literal: true

module DevTools
  # Development-only impersonation (AGENTS.md, "Development tools"). An
  # operator opens a session as another account from /devtools/impersonation:
  # their own session is parked in the Rails session, the cookie moves to a
  # fresh session for the target, and the bar above the topbar offers the way
  # back. Parking the operator's session is what makes the return free — no
  # password, no second factor.
  #
  # Included into ApplicationController by the engine so every controller
  # reads `impersonating?` and the sign-out path hands the browser back.
  module Impersonation
    extend ActiveSupport::Concern

    # The operator's parked session id. Not one of
    # Authentication::AUTHENTICATION_FLOW_KEYS, but cleared with the flow: it
    # is set after the target's sign-in and dropped by any later sign-in or
    # sign-out (#clear_authentication_flow).
    PARKED_SESSION_KEY = :dev_tools_impersonator_session_id

    included do
      helper_method :impersonating?, :impersonator
    end

    # True while the impersonation can be ended: the parked operator session
    # exists and is still usable.
    def impersonating? = parked_impersonator_session.present?

    # The operator whose session is parked.
    def impersonator = parked_impersonator_session&.user

    private

    # Opens a session as the target through the application's own sign-in
    # seam, so the cookie, its lifetime and `Current.session` behave exactly
    # as they do after a real sign-in.
    def start_impersonation(target)
      parked = Current.session
      start_new_session_for(target)
      session[PARKED_SESSION_KEY] = parked.id
    end

    # Ends the impersonation: the target's session row goes and the operator's
    # is put back on the cookie. A parked session that is no longer usable
    # signs the browser out instead of restoring anything.
    def stop_impersonation
      parked = parked_impersonator_session
      Current.session&.destroy
      session.delete(PARKED_SESSION_KEY)

      if parked
        parked.record_activity!
        Current.session = parked
        cookies.signed[:session_id] = { value: parked.id, expires: parked.expires_at, httponly: true, same_site: :lax }
      else
        Current.session = nil
        drop_session_cookie
      end
    end

    # Signing out while impersonating hands the browser back to the operator
    # instead of ending the browser session (SessionsController#destroy).
    def terminate_session
      impersonating? ? stop_impersonation : super
    end

    # The parked id belongs to the authentication flow: any sign-in or sign-out
    # drops it (Authentication#clear_authentication_flow), so a way back can
    # never survive into another account's session. `start_impersonation` sets
    # it after the sign-in seam that would clear it.
    def clear_authentication_flow
      session.delete(PARKED_SESSION_KEY)
      super
    end

    # The parked session, or nil once it expired or is gone. A parked session
    # that is no longer usable is forgotten: the browser is then plainly
    # signed in as the target.
    def parked_impersonator_session
      return @parked_impersonator_session if defined?(@parked_impersonator_session)

      id = session[PARKED_SESSION_KEY]
      parked = id && Session.find_by(id: id)
      parked = nil unless parked && !parked.expired? && parked.user && !parked.user.suspended?
      session.delete(PARKED_SESSION_KEY) if id && parked.nil?

      @parked_impersonator_session = parked
    end
  end
end
