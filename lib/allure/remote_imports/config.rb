# frozen_string_literal: true

module Allure
  module RemoteImports
    # Operator flags for the remote import sources (PLAN_REMOTE_IMPORTS.md §3),
    # read at call time like `Allure::Elevation::Config`. A provider whose flag
    # is unset is invisible: no card, no import panel, no job does anything.
    module Config
      FLAGS = {
        "garmin_connect" => "GARMIN_CONNECT_IMPORT_ENABLED",
        "exr" => "EXR_IMPORT_ENABLED",
        "withings" => "WITHINGS_IMPORT_ENABLED",
        "zwift" => "ZWIFT_IMPORT_ENABLED"
      }.freeze
      TRUE_VALUES = %w[1 true yes on].freeze

      module_function

      def providers = FLAGS.keys

      def enabled?(provider)
        key = FLAGS[provider.to_s]
        !key.nil? && TRUE_VALUES.include?(ENV[key].to_s.strip.downcase)
      end

      def enabled_providers = providers.select { |provider| enabled?(provider) }

      def any_enabled? = enabled_providers.any?
    end
  end
end
