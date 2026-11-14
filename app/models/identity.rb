# frozen_string_literal: true

# An identity at a provider linked to an account (PLAN_AUTH.md §4.4). The
# issuer and subject are the only key: an identity is never matched or linked
# by email.
class Identity < ApplicationRecord
  PROVIDERS = Allure::Auth::Providers::NAMES

  belongs_to :user

  validates :provider, inclusion: { in: PROVIDERS }, uniqueness: { scope: :user_id }
  validates :issuer, :subject, presence: true
  validates :subject, uniqueness: { scope: :issuer }

  def label = Allure::Auth::Providers.label_for(provider)
end
