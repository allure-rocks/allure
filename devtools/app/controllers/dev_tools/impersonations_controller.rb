# frozen_string_literal: true

module DevTools
  # Development-only impersonation (AGENTS.md, "Development tools"). The
  # operator lists the accounts on GET, opens a session as one on POST, and the
  # bar's button ends it on DELETE. Non-operators answer 404, exactly like the
  # administration console: the tool's existence is never confirmed to an
  # ordinary account.
  class ImpersonationsController < ApplicationController
    # How many accounts the list shows before it stops, with a note.
    LIST_LIMIT = 100

    # Starting an impersonation is privileged and asks for the same second
    # factor step-up as /admin. Listing the accounts is not: their names are
    # what /people already shows, and demanding the step-up on the way back
    # would drop the operator into re-authentication after a long
    # impersonation. `destroy` runs as the impersonated account, so it asks
    # only that an impersonation is active.
    before_action :require_operator, only: %i[show create]
    before_action :require_recent_second_factor, only: :create

    def show
      targets = User.where(suspended_at: nil).where.not(id: current_user.id)
      @accounts = targets.order(:username).limit(LIST_LIMIT)
      @more = targets.count > LIST_LIMIT
      @limit = LIST_LIMIT
    end

    def create
      target = User.find(params[:user_id])
      if target == current_user
        return redirect_to devtools_impersonation_path,
                           alert: t("dev_tools.impersonations.create.self_refused")
      end
      if target.suspended?
        return redirect_to devtools_impersonation_path,
                           alert: t("dev_tools.impersonations.create.suspended_refused")
      end

      operator = current_user.username
      start_impersonation(target)
      Rails.logger.info("[devtools] #{operator} is impersonating #{target.username}")

      redirect_to me_path, notice: t("dev_tools.impersonations.create.started", username: target.username)
    end

    def destroy
      raise ActiveRecord::RecordNotFound unless impersonating?

      operator = impersonator
      stop_impersonation
      Rails.logger.info("[devtools] impersonation ended, back as #{operator.username}")

      # The notice is read by the operator back on their own pages: it speaks
      # their locale, not the target's that was current during this request.
      notice = I18n.with_locale(operator.locale) do
        t("dev_tools.impersonations.destroy.stopped", username: operator.username)
      end

      redirect_to devtools_impersonation_path, notice:
    end

    private

    def require_operator
      raise ActiveRecord::RecordNotFound unless instance_operator?
    end
  end
end
