# frozen_string_literal: true

module Allure
  module RemoteImports
    # One photo a provider offers with an activity (PLAN_REMOTE_IMPORTS.md
    # §5.1): a readable, rewindable `io` the caller closes, and the filename the
    # source gave it. The photo pipeline detects the type from the bytes, so the
    # extension only names the object.
    Photo = Data.define(:io, :filename) do
      def initialize(io:, filename:) = super
    end
  end
end
