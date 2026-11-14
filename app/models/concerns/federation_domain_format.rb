# frozen_string_literal: true

# The authority form shared by peer policies and domain blocks: a host with an
# optional non-default port, never a scheme or path.
module FederationDomainFormat
  extend ActiveSupport::Concern

  DOMAIN_FORMAT = /\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)*(:\d{1,5})?\z/

  included do
    normalizes :domain, with: ->(domain) { domain.to_s.strip.downcase }
    validates :domain, presence: true
    validates :domain, format: { with: DOMAIN_FORMAT }, allow_blank: true
  end
end
