# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connected services" do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  describe "the hub" do
    it "lists an enabled provider with its state and opens its own page" do
      with_remote_import_enabled do
        get connections_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("settings.connections.states.disconnected"))
        expect(response.body).to include(%(href="#{connection_path("garmin_connect")}"))
      end
    end

    it "names a linked account and its last sync on the row" do
      create(:import_connection, :linked, user:)

      with_remote_import_enabled do
        get connections_path

        expect(response.body).to include(I18n.t("settings.connections.states.linked"))
        expect(response.body).to include(
          ERB::Util.html_escape(I18n.t("settings.connections.hub.linked_never", account: "Rider Garmin"))
        )
      end
    end

    it "keeps an existing connection visible, inert, once the operator disables the provider" do
      create(:import_connection, :linked, user:)

      with_remote_import_enabled(enabled: false) do
        get connections_path

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.connections.states.disabled")))
        expect(response.body).to include(%(href="#{connection_path("garmin_connect")}"))
      end
    end

    it "keeps the unlink action on a connection the operator disabled" do
      create(:import_connection, :linked, user:)

      with_remote_import_enabled(enabled: false) do
        get connection_path("garmin_connect")

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.connections.disabled", provider: "Garmin Connect")))
        expect(response.body).to include(%(id="delete-data-garmin_connect"))
      end
    end

    it "says so when nothing is enabled, and offers no entry" do
      with_remote_import_enabled(enabled: false) do
        get connections_path

        expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.connections.none_enabled")))
        expect(response.body).not_to include(%(href="#{connections_path}"))
      end
    end

    it "adds the account menu entry while a provider is enabled" do
      with_remote_import_enabled do
        get connections_path

        expect(response.body).to include(%(data-bridge-item="connections"), %(href="#{connections_path}"))
      end
    end

    it "never renders another account's connection" do
      create(:import_connection, :linked, external_account_name: "Someone Else")

      with_remote_import_enabled do
        get connections_path

        expect(response.body).not_to include("Someone Else")
      end
    end
  end

  describe "a service's page" do
    it "renders the section shell, the service navigation and the cards" do
      with_remote_import_enabled do
        get connection_path("garmin_connect")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("settings.connections.connection"))
        expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.connections.garmin_connect.privacy")))
        expect(response.body).to include(%(href="#{connections_path}"), "aria-current=\"page\"")
      end
    end

    it "answers a live-frame request with the cards alone" do
      with_remote_import_enabled do
        get connection_path("garmin_connect"), headers: { "Turbo-Frame" => "connection-garmin_connect-live" }
      end

      expect(response.body).to include(%(id="connection-garmin_connect"), "data-live-frame-done")
      expect(response.body).not_to include("<html", "page-header")
    end

    it "sends a service the account may not see back to the hub" do
      with_remote_import_enabled(enabled: false) do
        get connection_path("garmin_connect")
      end

      expect(response).to redirect_to(connections_path)
    end

    it "offers to reconnect and to unlink an expired connection" do
      create(:import_connection, :linked, user:).update!(status: "expired")

      with_remote_import_enabled do
        get connection_path("garmin_connect")

        expect(response.body).to include(I18n.t("settings.connections.garmin_connect.relink"))
        expect(response.body).to include(%(id="delete-data-garmin_connect"))
        expect(response.body).not_to include(%(id="retrieval_from_garmin_connect"))
      end
    end

    it "answers 404 for a provider the instance does not know" do
      get "/connections/strava"

      expect(response).to have_http_status(:not_found)
    end
  end

  it "sends the former settings address to the hub" do
    get "/settings/connections"

    expect(response).to redirect_to(connections_path)
  end
end
