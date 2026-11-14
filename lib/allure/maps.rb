# frozen_string_literal: true

module Allure
  module Maps
    class << self
      attr_writer :config

      def config = @config ||= Config.new
    end
  end
end
