# frozen_string_literal: true

module Admin
  # The operator's hand on an account's programmatic access (PLAN_API.md §14):
  # revoke an API token, disable a webhook. Both audited; the owner is told
  # (the security mail, the `webhook_disabled` notification). The operator
  # never sees a secret nor a webhook's full address.
  class ApiAccessController < BaseController
    def revoke_token
      account = User.find(params[:account_id])
      token = account.api_tokens.find_by_short_id!(params[:id])
      unless token.revoked?
        ApiTokens::Lifecycle.revoke!(token, by: "operator")
        Audit.record(actor: current_user, action: :api_token_revoked, subject: token,
                     metadata: { "username" => account.username, "token_prefix" => token.token_prefix })
      end
      redirect_to admin_account_path(account, anchor: "api"), notice: t("admin.accounts.api.flash.token_revoked"),
                                                              status: :see_other
    end

    def disable_webhook
      account = User.find(params[:account_id])
      endpoint = account.webhook_endpoints.find_by_short_id!(params[:id])
      unless endpoint.disabled?
        endpoint.disable!("operator")
        endpoint.deliveries.pending.update_all(status: "abandoned", last_error: "endpoint_disabled",
                                               next_attempt_at: nil, updated_at: Time.current)
        Audit.record(actor: current_user, action: :webhook_endpoint_disabled, subject: endpoint,
                     metadata: { "username" => account.username, "host" => endpoint.host })
      end
      redirect_to admin_account_path(account, anchor: "api"), notice: t("admin.accounts.api.flash.webhook_disabled"),
                                                              status: :see_other
    end
  end
end
