# frozen_string_literal: true

module Allure
  module Gpx
    ActivitySignal = Data.define(:source, :value) do
      def initialize(source:, value:)
        super(source: source.to_sym, value: value.to_s.strip.freeze)
      end
    end
  end
end
