# frozen_string_literal: true

# Security notices (docs/dev/AUTH.md): every change to how an account proves
# its identity is mailed to its address, so a change the person did not make
# is noticed. Localized to the account, since the mails are queued. API tokens
# act on the account's behalf, so their creation and revocation are mailed too
# (docs/dev/API.md).
class SecurityMailer < ApplicationMailer
  EVENTS = %w[
    totp_enrolled totp_removed passkey_added passkey_removed
    recovery_code_used recovery_codes_regenerated second_factor_reset
    identity_linked identity_unlinked password_added
    api_token_created api_token_revoked
  ].freeze

  def notice(user, event, remaining: nil, provider: nil, token_name: nil, mcp_geometry: nil)
    raise ArgumentError, "unknown security event #{event}" unless EVENTS.include?(event)

    @user = user
    @event = event
    @remaining = remaining
    @provider = provider
    @token_name = token_name
    # A token that may hand locations to an AI assistant says so (docs/dev/MCP.md).
    @mcp_geometry = mcp_geometry if ApiToken::MCP_GEOMETRY_LEVELS.excluding("none").include?(mcp_geometry)
    I18n.with_locale(user.locale) do
      mail subject: I18n.t("security_mailer.notice.subjects.#{event}", provider:, token: token_name), to: user.email_address
    end
  end
end
