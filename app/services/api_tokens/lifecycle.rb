# frozen_string_literal: true

module ApiTokens
  # Creating and revoking an API token (PLAN_API.md §4.4). Both are security
  # changes, so both are mailed to the account.
  module Lifecycle
    module_function

    # Returns [token, secret]; the secret is never stored.
    def issue!(user:, name:, scopes:, expires_in_days:, mcp_geometry: "none")
      token, secret = ApiToken.issue!(user:, name:, scopes:, expires_in_days:, mcp_geometry:)
      SecurityMailer.notice(user, "api_token_created", token_name: token.name,
                                                       mcp_geometry: token.mcp_geometry).deliver_later
      [ token, secret ]
    end

    def revoke!(token, by:)
      return if token.revoked?

      token.revoke!(by:)
      SecurityMailer.notice(token.user, "api_token_revoked", token_name: token.name).deliver_later
    end
  end
end
