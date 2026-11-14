# frozen_string_literal: true

module Users
  # Enqueued for every reset request, whatever the address. The lookup and the
  # delivery both happen here so the request path costs the same for an
  # existing and a missing account; a synchronous branch would leak account
  # existence through response timing.
  class PasswordResetJob < ApplicationJob
    queue_as :default

    def perform(email_address)
      user = User.find_by(email_address:)
      # A password-less account adds a password only from its settings, after
      # re-authenticating (PLAN_AUTH.md §5.6); the answer stays the same.
      return unless user&.password?

      PasswordsMailer.reset(user).deliver_now
    end
  end
end
