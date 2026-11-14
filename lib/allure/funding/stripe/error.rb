# frozen_string_literal: true

module Allure
  module Funding
    module Stripe
      class Error < Providers::ProviderError
        attr_reader :status

        def initialize(message, status: nil)
          @status = status
          super(message)
        end
      end
    end
  end
end
