# frozen_string_literal: true

module Auth
  # Resolves a verified provider answer (PLAN_AUTH.md §6.2) into what happens
  # next. The identity is looked up by its issuer and subject only; an email
  # never links or signs into an existing account.
  #
  # Intents: `sign_in` (the default), `link` (a signed-in, recently
  # re-authenticated account adds this identity), and `reauthenticate` (a
  # signed-in account proves itself again through an identity it owns).
  class ProviderSignIn
    Result = Data.define(:status, :user, :pending, :authenticated_at)

    INTENTS = %w[sign_in link reauthenticate].freeze
    PENDING_LIFETIME = 15.minutes
    # The claims read from the provider's verified answer besides the subject
    # and the email: carried to the iOS companion by the handoff (§9).
    PORTABLE_CLAIMS = %w[email_verified acr amr auth_time].freeze

    def initialize(auth:, provider:, intent: nil, current_session: nil, invitation_token: nil, now: Time.current)
      @auth = auth
      @provider = provider
      @intent = INTENTS.include?(intent.to_s) ? intent.to_s : "sign_in"
      @current_session = current_session
      @invitation_token = invitation_token.presence
      @now = now
    end

    # The parts of a verified OmniAuth answer this class reads, as plain JSON:
    # the iOS companion's handoff carries them from the system browser to the
    # app's web view (PLAN_AUTH.md §9). Rebuilt with OmniAuth::AuthHash.new.
    # The ID token itself never travels: only the verified claims.
    def self.portable(auth)
      reader = new(auth:, provider: nil)
      {
        "provider" => auth.provider.to_s,
        "uid" => auth.uid.to_s,
        "info" => {
          "email" => auth.info&.email, "name" => auth.info&.name, "nickname" => auth.info&.nickname,
          "email_verified" => reader.send(:email_verified?)
        },
        "extra" => { "raw_info" => PORTABLE_CLAIMS.index_with { |name| reader.send(:claim, name) }.compact }
      }
    end

    def call
      return result(:unverified_email) unless email.present? && email_verified?
      return result(:acr_refused) unless acr_accepted? && amr_accepted?

      case @intent
      when "link" then link
      when "reauthenticate" then reauthenticate
      else sign_in
      end
    end

    def subject = @auth.uid.to_s

    def issuer = @provider.issuer

    def email = @auth.info&.email.to_s.strip.downcase.presence

    # When the provider states when the person authenticated (`auth_time`,
    # OIDC Core §2), that moment is the proof of identity Allure records for
    # the session — never later than now. A single sign-on session days old
    # then owes a fresh proof before a sensitive action, exactly like a
    # password session. Google reports no `auth_time`.
    def authenticated_at
      value = claim("auth_time")
      return unless value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)

      [ Time.zone.at(value.to_i), @now ].min
    end

    private

    def current_user = @current_session&.user

    def identity = @identity ||= Identity.find_by(issuer:, subject:)

    def sign_in
      if identity
        return result(:suspended) if identity.user.suspended?

        identity.update!(email:, email_verified: true, last_used_at: @now)
        return result(:signed_in, user: identity.user, authenticated_at:)
      end

      invitation = RegistrationInvitation.find_by_token(@invitation_token) if @invitation_token
      account_email = invitation&.usable? ? invitation.email_address : email
      # Closed first: on a closed instance the answer is the same whether or
      # not the address belongs to an account, so a provider identity cannot
      # be used to find out.
      return result(:registration_closed) unless Allure::Registration.open? || invitation&.usable?
      return result(:email_taken) if User.exists?(email_address: account_email)

      result(:onboarding, pending: pending_identity(invitation, account_email))
    end

    def link
      return result(:stale) unless current_user && @current_session.recently_authenticated?(@now)

      if identity
        return result(identity.user_id == current_user.id ? :already_linked : :linked_elsewhere)
      end
      return result(:provider_already_linked) if current_user.identities.exists?(provider: @provider.name)

      current_user.identities.create!(provider: @provider.name, issuer:, subject:, email:, email_verified: true,
                                      linked_at: @now, last_used_at: @now)
      SecurityMailer.notice(current_user, "identity_linked", provider: @provider.label).deliver_later
      result(:linked, user: current_user)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      result(:linked_elsewhere)
    end

    # The provider was asked to authenticate the person again (`prompt=login`,
    # `max_age=0`); an answer that reports an older authentication is no
    # proof of identity. A provider that reports none is trusted on the request.
    def reauthenticate
      return result(:mismatch) unless current_user && identity&.user_id == current_user.id

      at = authenticated_at
      return result(:not_reauthenticated) if at && at < @now - Allure::Auth::Config.reauthentication_window

      identity.update!(email:, last_used_at: @now)
      result(:reauthenticated, user: current_user, authenticated_at: at)
    end

    def pending_identity(invitation, account_email)
      {
        "provider" => @provider.name,
        "issuer" => issuer,
        "subject" => subject,
        "email" => account_email,
        "provider_email" => email,
        "name" => (invitation.display_name if invitation&.usable?) || @auth.info&.name.to_s.strip.presence,
        "nickname" => @auth.info&.nickname.to_s.strip.presence,
        "invitation_token" => (@invitation_token if invitation&.usable?),
        "expires_at" => (@now + PENDING_LIFETIME).to_i
      }
    end

    # A verified claim: the openid_connect strategy merges the ID token into
    # `raw_info`, omniauth-apple keeps the decoded token under `id_info`.
    def claim(name)
      raw = @auth.extra&.raw_info
      value = raw&.dig(name)
      value.nil? ? raw&.dig("id_info", name) : value
    end

    # Providers report the flag as a boolean or as the string "true".
    def email_verified?
      candidates = [ @auth.info&.email_verified, claim("email_verified") ]
      candidates.any? { |value| value == true || value.to_s == "true" }
    end

    # A generic provider may be required to state the authentication context
    # it used (PLAN_AUTH.md §6.4). The claim comes from the strategy's
    # raw_info, into which omniauth_openid_connect merges the ID token's
    # claims after verifying its signature, issuer, audience, nonce and
    # expiry; this class never decodes a token itself.
    def acr_accepted?
      required = Allure::Auth::Providers.oidc_required_acr
      return true unless @provider.name == "oidc" && required

      claim("acr").to_s == required
    end

    # Likewise for an authentication method the token's `amr` must list.
    def amr_accepted?
      required = Allure::Auth::Providers.oidc_required_amr
      return true unless @provider.name == "oidc" && required

      Array(claim("amr")).map(&:to_s).include?(required)
    end

    def result(status, user: nil, pending: nil, authenticated_at: nil)
      Result.new(status:, user:, pending:, authenticated_at:)
    end
  end
end
