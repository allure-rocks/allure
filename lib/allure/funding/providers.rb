# frozen_string_literal: true

module Allure
  module Funding
    module Providers
      class VerificationError < StandardError; end
      class ProviderError < StandardError; end

      # Register adapters at boot, never from request parameters. Registration
      # alone does not enable an adapter or bypass the master switch.
      class Registry
        def initialize
          @adapters = {}
        end

        def register(adapter)
          slug = adapter.slug.to_s
          raise ArgumentError, "invalid funding provider" unless slug.match?(/\A[a-z0-9_]+\z/) && slug != "manual"
          return if @adapters[slug] == adapter
          raise ArgumentError, "duplicate funding provider" if @adapters.key?(slug)

          @adapters[slug] = adapter
        end

        def enabled
          return [] unless Funding.enabled?

          @adapters.values.select(&:enabled?)
        end

        def fetch(slug)
          return unless Funding.enabled?

          adapter = registered(slug)
          adapter if adapter&.enabled?
        end

        # Internal lifecycle work (notably account deletion) must still find an
        # adapter while the public feature switch is off. This never exposes a
        # checkout or webhook surface; the adapter's own credentials still gate
        # every provider operation.
        def registered(slug) = @adapters[slug.to_s]
      end

      REGISTRY = Registry.new

      module_function

      def register(adapter) = REGISTRY.register(adapter)
      def enabled = REGISTRY.enabled
      def fetch(slug) = REGISTRY.fetch(slug)
      def registered(slug) = REGISTRY.registered(slug)
    end
  end
end
