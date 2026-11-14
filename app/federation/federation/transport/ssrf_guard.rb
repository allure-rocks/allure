# frozen_string_literal: true

require "ipaddr"
require "socket"
require "timeout"
require "uri"

module Federation
  module Transport
    class SsrfGuard
      class UnsafeUri < StandardError; end
      ResolvedUri = Data.define(:uri, :addresses)
      # A stalled resolver must not hold the calling thread: a lookup that
      # does not answer in time fails like one that cannot resolve.
      RESOLVE_TIMEOUT = 3

      BLOCKED_NETWORKS = %w[
        0.0.0.0/8
        100.64.0.0/10
        192.0.0.0/24
        192.0.2.0/24
        198.18.0.0/15
        198.51.100.0/24
        203.0.113.0/24
        224.0.0.0/4
        240.0.0.0/4
        ::/128
        ::1/128
        2001:db8::/32
        2001::/32
        fec0::/10
        ff00::/8
      ].map { IPAddr.new(_1) }.freeze

      # IPv6 transition prefixes that carry an embedded IPv4 destination. The
      # dialed IPv6 address is global, but NAT64 and 6to4 gateways route it to
      # the embedded IPv4 address, so the guard has to validate that address.
      NAT64_NETWORKS = %w[
        64:ff9b::/96
        64:ff9b:1::/48
      ].map { IPAddr.new(_1) }.freeze
      SIX_TO_FOUR_NETWORK = IPAddr.new("2002::/16")

      def initialize(config: Allure::Federation.config, resolver: nil)
        @config = config
        @resolver = resolver || ->(host, port) { Socket.getaddrinfo(host, port, nil, :STREAM) }
      end

      def validate!(url)
        uri = parse_uri(url)
        validate_scheme!(uri)
        validate_authority!(uri)
        addresses = resolve(uri)
        validate_addresses!(addresses) unless private_ips_allowed?(uri)

        ResolvedUri.new(uri, addresses)
      end

      private

      def parse_uri(url)
        uri = URI.parse(url.to_s)
        raise UnsafeUri, "unsupported remote URI" unless uri.absolute? && uri.host.present?

        uri
      rescue URI::InvalidURIError, URI::InvalidComponentError
        raise UnsafeUri, "invalid remote URI"
      end

      def validate_scheme!(uri)
        allowed_http = uri.scheme == "http" && @config.protocol == "http" && @config.allow_private_ips?
        return if uri.scheme == "https" || allowed_http

        raise UnsafeUri, "remote URI must use HTTPS"
      end

      def validate_authority!(uri)
        raise UnsafeUri, "remote URI must not contain credentials or fragments" if uri.userinfo.present? || uri.fragment.present?
        raise UnsafeUri, "remote URI has an unsafe port" unless uri.port.between?(1024, 65_535) || [ 80, 443 ].include?(uri.port)
      end

      def resolve(uri)
        records = Timeout.timeout(RESOLVE_TIMEOUT) { @resolver.call(uri.host, uri.port) }
        addresses = records.filter_map do |record|
          address = if record.respond_to?(:ip_address)
            record.ip_address
          elsif record.is_a?(String)
            record
          else
            record[3]
          end
          IPAddr.new(address) if address.present?
        rescue IPAddr::InvalidAddressError
          nil
        end.uniq
        raise UnsafeUri, "remote host did not resolve" if addresses.empty?

        addresses
      rescue SocketError, IOError, Timeout::Error
        raise UnsafeUri, "remote host could not be resolved"
      end

      def validate_addresses!(addresses)
        return unless addresses.any? { |address| blocked_address?(address) }

        raise UnsafeUri, "remote host resolved to a private address"
      end

      def blocked_address?(address)
        # A NAT64 or 6to4 address hides the IPv4 destination the gateway will
        # dial, so validate that embedded address first. DNS64 on an IPv6-only
        # instance synthesizes NAT64 addresses for IPv4-only peers, so a public
        # embedded destination keeps working.
        embedded = embedded_ipv4(address)
        return blocked_address?(embedded) if embedded

        # `IPAddr` compares IPv4-mapped (`::ffff:a.b.c.d`) and IPv4-compatible
        # addresses as IPv6, so they never match the IPv4 entries of
        # BLOCKED_NETWORKS — `::ffff:0.0.0.0` would otherwise reach the local
        # stack. Normalize to the address family that will actually be dialed.
        address = address.native if address.respond_to?(:native)
        address.loopback? || address.private? || address.link_local? || BLOCKED_NETWORKS.any? { |network| network.include?(address) }
      end

      # The embedded IPv4 sits in the last 32 bits of a NAT64 address and in
      # bits 16–47 of a 6to4 address (RFC 6052, RFC 3056).
      def embedded_ipv4(address)
        return unless address.ipv6?

        bytes = address.hton
        if SIX_TO_FOUR_NETWORK.include?(address)
          IPAddr.new_ntoh(bytes[2, 4])
        elsif NAT64_NETWORKS.any? { |network| network.include?(address) }
          IPAddr.new_ntoh(bytes[12, 4])
        end
      end

      def private_ips_allowed?(uri)
        uri.scheme == "http" && @config.protocol == "http" && @config.allow_private_ips?
      end
    end
  end
end
