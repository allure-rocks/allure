# frozen_string_literal: true

module Auth
  # Passkeys and security keys (PLAN_AUTH.md §5.2). The relying party is this
  # instance: its ID is the federation host and its only origin the base URL,
  # both from Allure::Federation::Config. Challenges are single use and kept by
  # the caller in the encrypted Rails session.
  module Passkeys
    module_function

    def relying_party
      config = Allure::Federation.config
      WebAuthn::RelyingParty.new(allowed_origins: [ config.base_url ], id: config.host, name: Allure::Instance.name)
    end

    def registration_options(user)
      user.update!(webauthn_id: WebAuthn.generate_user_id) if user.webauthn_id.blank?
      relying_party.options_for_registration(
        user: { id: user.webauthn_id, name: user.handle, display_name: user.display_name },
        exclude: user.webauthn_credentials.pluck(:external_id),
        authenticator_selection: { resident_key: "preferred", user_verification: "preferred" }
      )
    end

    def authentication_options(user)
      relying_party.options_for_authentication(
        allow: user.webauthn_credentials.pluck(:external_id),
        user_verification: "preferred"
      )
    end

    # The new credential, or nil when the browser's answer does not verify.
    def register(user, raw, challenge:, nickname:)
      payload = parse(raw)
      return unless payload && challenge.present?

      credential = relying_party.verify_registration(payload, challenge)
      return unless credential

      user.webauthn_credentials.create!(
        external_id: credential.id,
        public_key: credential.public_key,
        sign_count: credential.sign_count,
        transports: Array(payload.dig("response", "transports")).grep(String).first(8),
        backed_up: credential.backed_up? || false,
        nickname:
      )
    rescue WebAuthn::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      nil
    end

    # The account's credential that signed the challenge, or nil.
    def authenticate(user, raw, challenge:, now: Time.current)
      payload = parse(raw)
      return unless payload && challenge.present?

      stored = user.webauthn_credentials.find_by(external_id: payload["id"].to_s)
      return unless stored

      credential = relying_party.verify_authentication(
        payload, challenge, public_key: stored.public_key, sign_count: stored.sign_count
      )
      return unless credential

      stored.update!(sign_count: credential.sign_count, backed_up: credential.backed_up? || false, last_used_at: now)
      stored
    rescue WebAuthn::Error
      nil
    end

    def parse(raw)
      payload = raw.is_a?(String) ? JSON.parse(raw) : nil
      payload.is_a?(Hash) ? payload : nil
    rescue JSON::ParserError
      nil
    end
  end
end
