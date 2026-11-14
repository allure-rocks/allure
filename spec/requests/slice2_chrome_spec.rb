# frozen_string_literal: true

require "rails_helper"

# M4 Slice 2 proofs: layout chrome (skip link, landmarks, bottom bar, topbar
# import action, fixed account menu), theme persistence, paginated feed,
# personal hub, public profile, and settings secondary navigation.
RSpec.describe "Slice 2 chrome" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def publish(workout, owner)
    profile = owner.publishing_profiles.find_by(built_in_key: "public") ||
      create(:publishing_profile, :without_endpoint_masks, user: owner)
    publish_workout!(user: owner, workout:, profile:)
  end

  describe "layout chrome" do
    it "renders skip link, landmarks, and bottom bar for signed-in users" do
      sign_in_as(user)

      get feed_path

      expect(response.body).to include('href="#main-content"', "Aller au contenu principal")
      expect(response.body).to include("<main", "<header", "<nav", "<footer")
      expect(response.body).to include('aria-label="Navigation principale"')
      expect(response.body).to include("bottom-bar-item")
      expect(response.body).to include(%(href="#{me_path}"), %(href="#{segments_path}"), %(href="#{settings_path}"))
    end

    it "redirects anonymous visitors before any chrome is rendered" do
      get feed_path

      expect(response).to redirect_to(new_session_path)
      expect(response.body).not_to include("bottom-bar-item")
    end

    it "offers import from the topbar and fixes the account menu" do
      sign_in_as(user)

      get feed_path

      expect(response.body).to include(%(href="#{new_workout_import_path}"))
      expect(response.body).to include(%(<span class="d-none d-lg-inline">Importer</span>))
      expect(response.body).to include(%(aria-label="Importer"))
      expect(response.body).to include(%(href="#{profile_path(user.username)}"))
      expect(response.body).to include(%(href="#{settings_path}"))
    end
  end

  describe "iOS companion chrome" do
    let(:native_agent) do
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " \
        "(KHTML, like Gecko) Mobile/15E148 Allure iOS/0.1.0 Hotwire Native iOS; " \
        "Turbo Native iOS; bridge-components: []"
    end

    it "drops the duplicated chrome and offers the server chooser" do
      sign_in_as(user)

      get workouts_path, headers: { "User-Agent" => native_agent }

      expect(response.body).to include(%(<body class="native-app">))
      expect(response.body).to include("<title>#{I18n.t('workouts.index.title', locale: :fr)}</title>")
      expect(response.body).not_to include("navbar-brand", "theme#toggle", "<footer")
      expect(response.body).to include("navbar-toggler", "bottom-bar-item", %(href="#{new_workout_import_path}"))
      expect(response.body).to include(%(href="#{ApplicationHelper::NATIVE_SERVER_PATH}"), "Serveur")
      expect(response.body).not_to include(%(data-controller="bridge--topbar"))
    end

    it "hands the topbar to the native bar when the app registers its bridge component" do
      sign_in_as(user)

      get workouts_path, headers: { "User-Agent" => native_agent.sub("[]", "[topbar]") }

      header = Nokogiri::HTML(response.body).at_css(%(header[data-controller="bridge--topbar"]))
      expect(header["class"].split).to include("d-none")
      payload = JSON.parse(header["data-bridge--topbar-payload-value"])
      menu = payload.dig("menu", "sections").flat_map { it["items"] }
      account = payload.dig("account", "sections").flat_map { it["items"] }

      expect(menu.find { it["id"] == "nav-workouts" })
        .to include("title" => "Activités", "icon" => "activity", "active" => true, "path" => workouts_path)
      expect(menu.find { it["id"] == "nav-people" }).to include("active" => false, "path" => people_path)
      expect(account.to_h { [ it["id"], it["path"] ] })
        .to eq("profile" => profile_path(user.username), "settings" => settings_path, "help" => help_path,
               "about" => nil, "server" => nil, "sign_out" => nil)
      expect(payload["account"]).to include("label" => "Menu du compte", "title" => user.display_name)
      expect(header.at_css(%([data-bridge--topbar-target="avatar"] svg))).to be_present
      expect(payload["notifications"]).to include("id" => "notifications", "unread" => false)
      expect(payload["notifications"]).not_to have_key("path")
      expect(payload["import"]).to eq("id" => "import", "label" => "Importer")
      (menu + account + [ payload["notifications"], payload["import"] ]).each do |entry|
        expect(header.at_css(%([data-bridge-item="#{entry['id']}"]))).to be_present, entry["id"]
      end
    end

    it "adds connected services to the account menu while the operator enables one" do
      sign_in_as(user)

      with_remote_import_enabled do
        get workouts_path, headers: { "User-Agent" => native_agent.sub("[]", "[topbar]") }
      end

      header = Nokogiri::HTML(response.body).at_css(%(header[data-controller="bridge--topbar"]))
      payload = JSON.parse(header["data-bridge--topbar-payload-value"])
      account = payload.dig("account", "sections").flat_map { it["items"] }

      expect(account.find { it["id"] == "connections" })
        .to include("title" => "Services connectés", "icon" => "plug-connected", "path" => connections_path)
      expect(header.at_css(%([data-bridge-item="connections"]))).to be_present
    end

    it "keeps the browser chrome and never links the server chooser" do
      sign_in_as(user)

      get workouts_path

      expect(response.body).to include("<body>", "navbar-brand", "theme#toggle", "<footer", " · Allure</title>")
      expect(response.body).not_to include(ApplicationHelper::NATIVE_SERVER_PATH, "native-app")
    end

    it "drops the theme toggle from the sign-in page" do
      get new_session_path, headers: { "User-Agent" => native_agent }

      expect(response.body).to include(%(<body class="native-app">))
      expect(response.body).not_to include("theme#toggle")
    end

    it "takes the companion's own appearance from its cookie" do
      sign_in_as(user)

      cookies["allure_companion_theme"] = "dark"
      get workouts_path, headers: { "User-Agent" => native_agent }

      expect(Nokogiri::HTML(response.body).at_css("html")["data-bs-theme"]).to eq("dark")
    end

    it "ignores the companion cookie in a browser and unknown values" do
      sign_in_as(user)

      cookies["allure_companion_theme"] = "dark"
      get workouts_path
      expect(Nokogiri::HTML(response.body).at_css("html")["data-bs-theme"]).to eq("light")

      cookies["allure_companion_theme"] = "sepia"
      get workouts_path, headers: { "User-Agent" => native_agent }
      expect(Nokogiri::HTML(response.body).at_css("html")["data-bs-theme"]).to eq("light")
    end

    it "hides the account theme card the companion overrides" do
      sign_in_as(user)

      get settings_appearance_path, headers: { "User-Agent" => native_agent }
      expect(response.body).not_to include("user[theme]")

      get settings_appearance_path
      expect(response.body).to include("user[theme]")
    end

    it "hands the phone bottom bar to native tabs" do
      sign_in_as(user)

      get workouts_path, headers: { "User-Agent" => native_agent.sub("[]", "[topbar tabs]") }

      body = Nokogiri::HTML(response.body)
      expect(body.at_css("body")["class"].split).to include("native-tabs")
      bar = body.at_css(%(nav[data-controller="bridge--tabs"]))
      expect(bar["class"].split).to include("d-none")
      payload = JSON.parse(bar["data-bridge--tabs-payload-value"])
      expect(payload["tabs"].map { it["id"] })
        .to eq(%w[tab-feed tab-me tab-workouts tab-segments tab-people])
      expect(payload["tabs"].find { it["id"] == "tab-workouts" })
        .to include("title" => "Activités", "icon" => "activity", "path" => workouts_path, "active" => true)
      expect(payload["tabs"].find { it["id"] == "tab-people" })
        .to include("title" => "Personnes", "icon" => "users", "path" => people_path, "active" => false)
      expect(bar.css("a").size).to eq(5)
    end

    it "keeps the web bottom bar for a companion without the tabs component" do
      sign_in_as(user)

      get workouts_path, headers: { "User-Agent" => native_agent.sub("[]", "[topbar]") }

      body = Nokogiri::HTML(response.body)
      expect(body.at_css(%(nav[data-controller="bridge--tabs"]))).to be_nil
      expect(body.at_css("body")["class"].split).not_to include("native-tabs")
      expect(body.at_css(".bottom-bar-item")).to be_present
    end
  end

  describe "theme persistence" do
    it "persists a valid theme choice" do
      sign_in_as(user)

      patch settings_appearance_path, params: { theme: "dark" }

      expect(response).to have_http_status(:no_content)
      expect(user.reload.theme).to eq("dark")
    end

    it "rejects an unknown theme" do
      sign_in_as(user)

      patch settings_appearance_path, params: { theme: "neon" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.theme).to eq("light")
    end

    it "redirects anonymous visitors" do
      patch settings_appearance_path, params: { theme: "dark" }

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "feed" do
    it "paginates past twelve publications" do
      titles = Array.new(13) { |i| "Feed workout #{i}" }
      titles.each do |title|
        workout = create(:workout, user:, sport:, title:)
        create(:track_segment, workout:)
        publish(workout, user)
      end
      sign_in_as(user)

      get feed_path
      expect(response.body).to include("Feed workout 12")
      expect(response.body).to include("pagination")

      get feed_path(page: 2)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Feed workout 0")
    end

    it "shows only published workouts to another member" do
      published = create(:workout, user:, sport:, title: "Visible public ride")
      create(:track_segment, workout: published)
      publish(published, user)
      create(:workout, user:, sport:, title: "Hidden private ride")
      sign_in_as(create(:user))

      get feed_path

      expect(response.body).to include("Visible public ride")
      expect(response.body).not_to include("Hidden private ride")
    end
  end

  describe "personal hub" do
    it "renders tiles, calendar, regularity, segments, and records" do
      create(:workout, user:, sport:)
      sign_in_as(user)

      get me_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("@#{user.username}", "1 activité")
      expect(response.body).to include("Activités", "Distance", "Dénivelé", "Temps")
      expect(response.body).to include('data-controller="calendar"')
      expect(response.body).to include("Régularité", "Derniers records", "Segments récents")
      expect(response.body).to include(%(href="#{stats_path}"), %(href="#{records_path}"), %(href="#{segments_path}"))
    end

    it "filters tiles by period and defaults invalid periods to the last 30 days" do
      create(:workout, user:, sport:, started_at: 10.days.ago)
      create(:workout, user:, sport:, started_at: 60.days.ago)
      sign_in_as(user)

      get me_path(period: "days30")
      expect(response.body).to include(">1<")

      get me_path(period: "all")
      expect(response.body).to include(">2<")

      get me_path(period: "bogus")
      expect(response.body).to include(">1<")
    end

    it "shows an import empty state with no workouts" do
      sign_in_as(user)

      get me_path

      expect(response.body).to include("Rien ici pour l&#39;instant")
    end
  end

  describe "profile" do
    it "does not provision a federation actor when federation is disabled" do
      previous = ENV["FEDERATION_ENABLED"]
      ENV["FEDERATION_ENABLED"] = "false"
      sign_in_as(user)

      expect {
        get profile_path(user.username)
      }.not_to change(Actor, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("application/activity+json")
    ensure
      previous.nil? ? ENV.delete("FEDERATION_ENABLED") : ENV["FEDERATION_ENABLED"] = previous
    end

    it "shows published workouts only, even to the owner" do
      published = create(:workout, user:, sport:, title: "Shared race")
      create(:track_segment, workout: published)
      publish(published, user)
      create(:workout, user:, sport:, title: "Private training")
      sign_in_as(user)

      get profile_path(user.username)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Shared race")
      expect(response.parsed_body.at_css("#profile-journal-title").text).to eq(I18n.t("profile.journal.title"))
      expect(response.body).not_to include("Private training")
    end

    it "shows strangers published workouts only" do
      published = create(:workout, user:, sport:, title: "Shared race")
      create(:track_segment, workout: published)
      publish(published, user)
      create(:workout, user:, sport:, title: "Hidden training")
      stranger = create(:user)
      sign_in_as(stranger)

      get profile_path(user.username)

      expect(response.body).to include("Shared race")
      expect(response.body).not_to include("Hidden training")
    end

    it "renders an empty state with no visible workouts" do
      sign_in_as(create(:user))

      get profile_path(user.username)

      expect(response.parsed_body.at_css(".empty-title").text).to eq(I18n.t("profile.empty.title"))
    end

    it "redirects an anonymous visitor and returns 404 for unknown usernames" do
      get profile_path(user.username)
      expect(response).to redirect_to(new_session_path)

      sign_in_as(create(:user))
      get profile_path("ghost")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "settings secondary navigation" do
    it "persists across profile, collections, and security" do
      sign_in_as(user)

      [ settings_profile_path, publishing_profiles_path,
        privacy_zones_path, settings_security_path ].each do |path|
        get path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(href="#{settings_security_path}"), ">Sécurité</a>")
      end
    end

    it "renders the universal settings entry as a hub" do
      sign_in_as(user)

      get settings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{settings_profile_path}"), %(href="#{settings_security_path}"))
    end
  end
end
