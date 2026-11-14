# frozen_string_literal: true

module Allure
  module RemoteImports
    # The original file of one remote activity and what the provider says
    # about it (PLAN_REMOTE_IMPORTS.md §5.1). `io` is readable and rewindable;
    # `filename` carries the extension the importer recognises. `declared_sport`
    # is a catalog slug the provider's listing named (Withings's `subcategory`,
    # §7c.3): it outranks the file's own detection exactly as the Strava
    # archive's declared type does, and stays `nil` for every other provider.
    FetchedActivity = Data.define(:io, :filename, :title, :description, :commute,
                                  :equipment_external_id, :device_name, :declared_sport, :metadata) do
      def initialize(io:, filename:, title: nil, description: nil, commute: nil,
                     equipment_external_id: nil, device_name: nil, declared_sport: nil, metadata: {})
        super
      end
    end
  end
end
