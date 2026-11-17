# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :screenshot, :screenshot_base64, :privacy_zone, :latitude, :longitude, :radius_meters, :center,
  # Authentication proofs (docs/dev/AUTH.md): authenticator, recovery
  # and Garmin MFA codes, OAuth authorization codes, passkey responses, and the
  # iOS handoff's PKCE verifier. An unspent recovery code stays valid
  # indefinitely, so none of them may reach a log.
  :code, :verifier, :assertion, :credential,
  # The push subscription's proof (PLAN_PUSH.md §5): the session-less
  # `POST /push/unsubscribe` is authorized by the endpoint and its `auth`
  # secret alone, and knowing an endpoint is enough to replace the
  # registration it names. Neither may reach a log.
  :endpoint, :auth,
  # Sign in with Apple posts the person's name and email as one JSON string
  # named `user`, which the :email filter cannot see into. Matched by value
  # type, because a `user` key filter would also mask every user[...] form.
  ->(key, value) { value.replace("[FILTERED]") if key.to_s == "user" && value.is_a?(String) && !value.frozen? },
  # Provider payment payloads (PAY-102): the funding webhook controller never
  # logs its parsed body (it is replaced by a minimal envelope before Rails
  # logs request parameters), but these mask the billing keys anywhere else,
  # nested objects included — a matched key masks its whole subtree, so a
  # `name` inside `customer_details` cannot slip through a key rename.
  /client_reference_id/, /billing/, /address/, /invoice/, /customer/, /charge/
]

# Rails logs redirect locations verbatim. The iOS companion's handoff carries
# its single-use token in the location (docs/dev/AUTH.md).
Rails.application.config.filter_redirect << %r{\Aallure://auth/handoff}
