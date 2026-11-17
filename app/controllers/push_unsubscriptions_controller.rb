# frozen_string_literal: true

# `POST /push/unsubscribe` (docs/dev/PUSH.md): the companion calls it natively
# when it leaves this server, just before its web data is wiped, so it has no
# session and no CSRF token. Knowing the device's `auth` secret is the proof.
# The answer is 204 whether anything matched, so it reveals nothing.
class PushUnsubscriptionsController < ActionController::API
  rate_limit to: 30, within: 1.minute, with: -> { head :too_many_requests }

  def create
    subscription = PushSubscription.find_by_endpoint(params[:endpoint].to_s)
    auth = params[:auth].to_s
    if subscription && auth.present? && proof_matches?(subscription, auth)
      subscription.destroy!
    end
    head :no_content
  end

  private

  def proof_matches?(subscription, auth)
    given = Allure::Push::Config.decode(auth)
    expected = Allure::Push::Config.decode(subscription.auth)
    return false unless given && expected && given.bytesize == expected.bytesize

    ActiveSupport::SecurityUtils.secure_compare(given, expected)
  end
end
