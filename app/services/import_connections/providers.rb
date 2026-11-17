# frozen_string_literal: true

module ImportConnections
  # Builds the provider adapter of a connection (docs/dev/REMOTE-IMPORTS.md).
  # An adapter is built from one `ImportConnection`, persists the tokens it
  # refreshes on that row, and answers the duck-typed surface pinned by
  # `spec/support/shared_examples/import_provider.rb`:
  #
  #   list(from:, to:)  -> Enumerable of Allure::RemoteImports::RemoteActivity
  #   fetch(activity)   -> Allure::RemoteImports::FetchedActivity
  #   photos(activity)  -> Allure::RemoteImports::PhotoSet
  #   equipment         -> Enumerable of Allure::RemoteImports::RemoteEquipment
  #   deauthorize!      -> best effort, never raises
  #
  # and raises only `Allure::RemoteImports::Error` subclasses.
  module Providers
    # provider key => adapter class name.
    ADAPTERS = {
      "garmin_connect" => "ImportConnections::Providers::GarminConnect",
      "exr" => "ImportConnections::Providers::Exr",
      "withings" => "ImportConnections::Providers::Withings",
      "zwift" => "ImportConnections::Providers::Zwift"
    }.freeze

    # What a provider offers beyond listing and fetching: gear to retrieve, a
    # fallback sport for files that name none (an EXR file always names its
    # platform, so it needs neither), and a session whose end the card shows
    # (EXR's five-year cookie, Withings's day, Zwift's eight-day refresh token,
    # docs/dev/REMOTE-IMPORTS.md).
    CAPABILITIES = {
      "garmin_connect" => %i[equipment fallback_sport],
      "exr" => %i[session_expiry],
      "withings" => %i[fallback_sport session_expiry route_filter],
      "zwift" => %i[session_expiry]
    }.freeze

    module_function

    def supports?(provider, capability) = CAPABILITIES.fetch(provider.to_s, []).include?(capability)

    def for(connection)
      name = ADAPTERS.fetch(connection.provider) do
        raise ArgumentError, "no adapter for provider #{connection.provider.inspect}"
      end
      name.constantize.new(connection)
    end
  end
end
