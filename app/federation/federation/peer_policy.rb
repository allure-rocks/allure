# frozen_string_literal: true

module Federation
  # Reads the locally assigned capability for a remote authority. A remote
  # document's own claims are never consulted.
  module PeerPolicy
    module_function

    def capability_for(uri_or_domain)
      domain = Allure::Federation::Authority.domain(uri_or_domain) || uri_or_domain.to_s
      FederationPeerPolicy.find_by(domain:)&.capability_profile
    end
  end
end
