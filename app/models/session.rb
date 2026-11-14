# frozen_string_literal: true

# A signed-in browser (PLAN_AUTH.md §8). It lives until sign-out or
# revocation, and at most until it has been idle for the idle timeout or has
# reached its absolute lifetime, whichever comes first.
class Session < ApplicationRecord
  belongs_to :user
  # Removed with the session by the foreign-key cascade (PLAN_PUSH.md §1.5),
  # including the sweeps that delete expired rows in bulk.
  has_one :push_subscription, dependent: :delete

  SECOND_FACTOR_METHODS = %w[totp webauthn recovery_code].freeze
  AUTH_METHODS = [ "password", *Allure::Auth::Providers::NAMES.map { |name| "provider:#{name}" } ].freeze

  attribute :last_seen_at, default: -> { Time.current }

  validates :second_factor_method, inclusion: { in: SECOND_FACTOR_METHODS }, allow_nil: true
  validates :auth_method, inclusion: { in: AUTH_METHODS }

  # The provider name for a provider sign-in, nil for the password.
  def provider
    auth_method.delete_prefix("provider:") if auth_method.start_with?("provider:")
  end

  scope :expired, ->(now = Time.current) {
    where(last_seen_at: ..(now - Allure::Auth::Config.session_idle_timeout))
      .or(where(created_at: ..(now - Allure::Auth::Config.session_max_lifetime)))
  }
  scope :live, ->(now = Time.current) {
    where(last_seen_at: (now - Allure::Auth::Config.session_idle_timeout)..)
      .where(created_at: (now - Allure::Auth::Config.session_max_lifetime)..)
  }

  def expired?(now = Time.current)
    last_seen_at <= now - Allure::Auth::Config.session_idle_timeout || created_at <= now - Allure::Auth::Config.session_max_lifetime
  end

  # The cookie never outlives the absolute lifetime.
  def expires_at = created_at + Allure::Auth::Config.session_max_lifetime

  # Activity is recorded at most once per refresh interval, so an ordinary page
  # view does not write to the database.
  def record_activity!(now = Time.current)
    return if last_seen_at > now - Allure::Auth::Config.last_seen_refresh

    update_column(:last_seen_at, now)
  end

  def recently_authenticated?(now = Time.current)
    reauthenticated_at.present? && reauthenticated_at > now - Allure::Auth::Config.reauthentication_window
  end

  def reauthenticate!(now = Time.current, second_factor: nil)
    attributes = { reauthenticated_at: now }
    attributes.merge!(second_factor_method: second_factor.to_s, second_factor_at: now) if second_factor
    update!(attributes)
  end

  # The operator console re-confirms a second factor (PLAN_AUTH.md §5.4).
  def recent_second_factor?(now = Time.current)
    second_factor_at.present? && second_factor_at > now - Allure::Auth::Config.step_up_window
  end

  def complete_enrolment!(now = Time.current, method:)
    update!(enrolment_only: false, second_factor_method: method.to_s, second_factor_at: now, reauthenticated_at: now)
  end
end
