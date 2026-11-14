# frozen_string_literal: true

# Demo mode's shared playground accounts (PLAN_DEMO.md §3). Their credentials
# are published on the sign-in page, so no visitor may lock the next one out:
# every mutation of the account's credential state is refused server-side —
# never merely hidden in the UI. Everything else stays writable, which is the
# point of the demo; the nightly reset heals the rest.
#
# Controllers opt in per action:
#
#     before_action :refuse_demo_account_lockout, only: :create
#
module DemoAccounts
  extend ActiveSupport::Concern

  private

  def refuse_demo_account_lockout
    return unless Allure::Demo.shared_account?(current_user)

    redirect_back_or_to root_path, alert: t("demo.account_locked"), status: :see_other
  end
end
