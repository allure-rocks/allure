# frozen_string_literal: true

module Federation
  module Safety
    # The instance-level block check (docs/dev/FEDERATION.md). An actor block names one
    # actor URI. A domain block without a port covers the host, every
    # subdomain and every port, so a blocked operator cannot come back as
    # `x.evil.example` or `evil.example:8443`; a domain block with a port
    # covers exactly that authority.
    module Blocks
      AUTHORITY_WITH_PORT = /\A(?<host>.+):(?<port>\d+)\z/

      module_function

      def blocked_actor?(actor_uri)
        return false if actor_uri.blank?

        FederationActorBlock.exists?(actor_uri: actor_uri.to_s)
      end

      def blocked_domain?(domain)
        candidates = domain_candidates(domain)
        return false if candidates.empty?

        FederationDomainBlock.exists?(domain: candidates)
      end

      # Whether a block on `block_domain` covers the authority `domain`.
      def covers?(block_domain, domain)
        domain_candidates(domain).include?(block_domain.to_s.strip.downcase)
      end

      # The block values that cover an authority: the authority itself, then
      # its host without the port and each parent of that host. An IP literal
      # has no parents.
      def domain_candidates(domain)
        authority = domain.to_s.strip.downcase
        return [] if authority.blank?

        host = authority.match(AUTHORITY_WITH_PORT)&.[](:host) || authority
        return [ authority, host ].uniq if Allure::Federation::Authority.ip_literal?(host)

        labels = host.split(".")
        ([ authority ] + labels.each_index.map { |index| labels.drop(index).join(".") }).uniq
      end

      def blocked?(actor_uri)
        blocked_actor?(actor_uri) || blocked_domain?(Allure::Federation::Authority.domain(actor_uri))
      end

      # The subset of the given actor URIs this instance blocks, by actor or by
      # domain, in two queries: a page that names many reactors never asks per
      # actor (docs/dev/REACTIONS.md).
      def blocked_uris(actor_uris)
        uris = Array(actor_uris).compact_blank
        return Set.new if uris.empty?

        blocked_actors = FederationActorBlock.where(actor_uri: uris).pluck(:actor_uri).to_set
        blocked_domains = FederationDomainBlock.pluck(:domain).to_set
        uris.each_with_object(Set.new) do |uri, blocked|
          domain = Allure::Federation::Authority.domain(uri)
          blocked << uri if blocked_actors.include?(uri) || domain_candidates(domain).any? { blocked_domains.include?(_1) }
        end
      end
    end
  end
end
