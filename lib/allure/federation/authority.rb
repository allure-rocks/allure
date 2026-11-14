# frozen_string_literal: true

require "ipaddr"
require "uri"

module Allure
  module Federation
    # The normalized authority of a federated URI: host, plus the port when it
    # is not the scheme default. Per-domain policy, blocking, and rate limiting
    # all key on this exact string, so it is derived in one place. A host is a
    # DNS name and therefore case-insensitive, so it is folded to lower case;
    # without that, a peer could rotate the case of its actor URIs to earn a
    # fresh rate-limit bucket or slip past an actor block.
    module Authority
      module_function

      def domain(uri)
        parsed = URI.parse(uri.to_s)
        return if parsed.host.blank?

        host = parsed.host.downcase
        default_port = parsed.scheme == "https" ? 443 : 80
        parsed.port == default_port ? host : "#{host}:#{parsed.port}"
      rescue URI::InvalidURIError, URI::InvalidComponentError
        nil
      end

      # A coarse site for metering: the host's last two labels, without the
      # port. A wildcard DNS zone mints unlimited authorities
      # (`a1.attacker.example`, `a2.…`) that all share this site. It is not
      # the registrable domain (no public-suffix list), so `*.co.uk` share one
      # site too; the limits keyed on it are generous for that reason.
      def site(uri)
        host = URI.parse(uri.to_s).host&.downcase
        return if host.blank?
        return host if ip_literal?(host)

        host.split(".").last(2).join(".")
      rescue URI::InvalidURIError, URI::InvalidComponentError
        nil
      end

      def ip_literal?(host)
        IPAddr.new(host.delete_prefix("[").delete_suffix("]"))
        true
      rescue IPAddr::InvalidAddressError
        false
      end

      # An actor URI compared for blocking: the scheme and host are
      # case-insensitive while the path is not, so only those are folded and
      # the rest of the URI is preserved.
      def normalize_uri(uri)
        parsed = URI.parse(uri.to_s)
        return uri.to_s if parsed.host.blank?

        normalized = parsed.dup
        normalized.host = parsed.host.downcase
        normalized.to_s
      rescue URI::InvalidURIError, URI::InvalidComponentError, NoMethodError
        uri.to_s
      end
    end
  end
end
