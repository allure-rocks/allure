# frozen_string_literal: true

require "digest"

module Federation
  module Safety
    # Meters the signer fetches an unauthenticated request can cause
    # (docs/dev/FEDERATION.md). The admission limit counts admitted rows only, and a
    # request whose signature does not verify leaves none, so every attempt
    # that reaches a fetch is counted here instead, per authority and per
    # site (`Allure::Federation::Authority.site`, which wildcard subdomains
    # share). An actor whose fetch or verification just failed is not fetched
    # again for a short while: the request is asked to retry, so a forged
    # signature naming an honest actor cannot turn every request into a fetch
    # of it, while a peer that really rotated its key gets through on a later
    # retry.
    #
    # Counters live in `Rails.cache`, like the controllers' `rate_limit`: per
    # process when the store is, and lost on restart, which is acceptable for
    # a limit whose hard guarantee is `ResolutionGate`.
    module ResolutionAttempts
      WINDOW = 1.minute
      PER_AUTHORITY = 30
      PER_SITE = 60
      FAILURE_TTL = 5.minutes

      class Exceeded < StandardError
        attr_reader :retry_after

        def initialize(retry_after)
          @retry_after = retry_after
          super("signer resolution limit exceeded")
        end
      end

      class RecentlyFailed < ActorResolver::Unavailable; end

      class << self
        attr_writer :store

        def store = @store || Rails.cache

        def check!(actor_uri, now: Time.current)
          raise RecentlyFailed, "signer resolution failed recently" if store.read(failure_key(actor_uri))

          window = now.to_i / WINDOW.to_i
          buckets(actor_uri).each do |scope, value, limit|
            count = store.increment("federation:signer_resolution:#{scope}:#{value}:#{window}", 1,
                                    expires_in: WINDOW * 2).to_i
            raise Exceeded, (WINDOW.to_i - (now.to_i % WINDOW.to_i)) if count > limit
          end
        end

        def record_failure(actor_uri)
          store.write(failure_key(actor_uri), true, expires_in: FAILURE_TTL)
        end

        private

        def buckets(actor_uri)
          [
            [ "authority", Allure::Federation::Authority.domain(actor_uri), PER_AUTHORITY ],
            [ "site", Allure::Federation::Authority.site(actor_uri), PER_SITE ]
          ].select { |_scope, value, _limit| value.present? }
        end

        def failure_key(actor_uri)
          "federation:signer_resolution:failed:#{Digest::SHA256.hexdigest(actor_uri.to_s)}"
        end
      end
    end
  end
end
