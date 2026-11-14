# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Feed" do
  # The root path dispatches by session: members land on their personal hub.
  # A visitor meets the sign-in gate and returns to `/` afterwards.
  it "sends visitors to sign-in and members to their personal hub" do
    get root_path
    expect(response).to redirect_to(new_session_path)

    sign_in_as(create(:user))
    get root_path
    expect(response).to redirect_to(me_path)
  end

  # Viewing requires an account (PLAN_MEMBERS_ONLY.md): no feed surface is
  # rendered to an anonymous visitor.
  it "redirects an anonymous visitor to sign-in" do
    get feed_path

    expect(response).to redirect_to(new_session_path)
  end

  it "loads its JavaScript from Vite" do
    sign_in_as(create(:user))

    get feed_path

    expect(response.body).to match(%r{<script[^>]+src="/vite-(dev|test|prod)/})
  end

  # Inspira shipped Propshaft, importmap and Vite simultaneously, with the
  # first two silently dead. Keeping exactly one asset pipeline is a deliberate
  # constraint, so it is asserted rather than assumed.
  it "has no second asset pipeline installed" do
    expect(Bundler.load.specs.map(&:name)).not_to include("propshaft", "sprockets-rails", "importmap-rails")
  end

  it "offers the Public switch to signed-in members" do
    sign_in_as(create(:user))

    get feed_path

    expect(response.body).to include('id="feed-public"', I18n.t("feed.public.label"))
  end

  it "shows recent public publications without the hardcoded smoke-test route" do
    public_workout = create(:workout, title: "Public morning ride")
    create(:track_segment, workout: public_workout)
    profile = create(:publishing_profile, :without_endpoint_masks, user: public_workout.user)
    publication = publish_workout!(user: public_workout.user, workout: public_workout, profile:)
    create(:workout, title: "Hidden draft ride")
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer).to receive(:call)
      .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "no browser")
    Workouts::RenderPublicationRouteImageJob.perform_now(publication)
    sign_in_as(create(:user))

    get feed_path

    expect(response.body).to include("Public morning ride")
    expect(response.body).not_to include("Hidden draft ride", "data-map-track-value", "6.4074")
    expect(response.body).not_to include(workout_route_image_path(public_workout))
    # The default profile carries the sanitized route image on the card, through
    # the browser media endpoint, never the signed wire one.
    expect(response.body).to include(publication_route_image_path(publication))
    expect(response.body).not_to include(workout_publication_route_image_path(publication))
  end

  it "names the owner of every publication" do
    owner = create(:user, display_name: "Marie Dufour", username: "marie")
    workout = create(:workout, user: owner, title: "Owned ride")
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publish_workout!(user: owner, workout:, profile:)
    sign_in_as(create(:user))

    get feed_path

    expect(response.body).to include("Marie Dufour", "@marie", profile_path("marie"))
  end

  it "shows the owner's active publications but never their drafts" do
    user = create(:user, locale: "en")
    published = create(:workout, user:, title: "Shared morning ride")
    create(:track_segment, workout: published)
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    publish_workout!(user:, workout: published, profile:)
    draft = create(:workout, user:, title: "Unpublished evening run")
    sign_in_as(user)

    get feed_path

    expect(response.body).to include("Shared morning ride", "Feed", workouts_path)
    expect(response.body).not_to include("Unpublished evening run")
    expect(response.body).not_to include(workout_route_image_path(draft))
  end

  it "renders the published snapshot instead of later source edits" do
    user = create(:user)
    workout = create(:workout, user:, title: "Shared title")
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    publish_workout!(user:, workout:, profile:)
    workout.update!(title: "Edited source title")
    sign_in_as(user)

    get feed_path

    expect(response.body).to include("Shared title")
    expect(response.body).not_to include("Edited source title")
  end

  it "orders the feed by publication date, not activity date" do
    user = create(:user)
    older_activity = create(:workout, user:, title: "Older activity, published last",
                                      started_at: Time.zone.parse("2026-08-20 06:00:00"))
    create(:track_segment, workout: older_activity)
    newer_activity = create(:workout, user:, title: "Newer activity, published first",
                                      started_at: Time.zone.parse("2026-08-23 06:00:00"))
    create(:track_segment, workout: newer_activity)
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    newer_publication = publish_workout!(user:, workout: newer_activity, profile:)
    older_publication = publish_workout!(user:, workout: older_activity, profile:)
    WorkoutPublication.where(id: newer_publication.id)
      .update_all(published_at: Time.zone.parse("2026-08-24 08:00:00"))
    WorkoutPublication.where(id: older_publication.id)
      .update_all(published_at: Time.zone.parse("2026-08-25 08:00:00"))
    sign_in_as(user)

    get feed_path

    expect(response.body.index("Older activity, published last")).to be < response.body.index("Newer activity, published first")
  end

  it "hides followers-only publications from unrelated members" do
    user = create(:user)
    workout = create(:workout, user:, title: "Followers-only ride")
    create(:track_segment, workout:)
    create(:workout_publication, :with_followers, workout:)
    sign_in_as(create(:user))

    get feed_path

    expect(response.body).not_to include("Followers-only ride")
  end

  it "reaches settings from the account menu and privacy zones from the hub" do
    user = create(:user)
    sign_in_as(user)

    get feed_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Paramètres", settings_path)
    expect(response.body).not_to include(privacy_zones_path)

    get settings_profile_path

    expect(response.body).to include("Zones de confidentialité", privacy_zones_path)
  end

  describe "navigation" do
    # NavigationHelper skips entries whose route helper does not exist yet, so
    # config/navigation.rb can describe the finished app while routes are still
    # being built. Without this the whole site 500s on every page.
    it "omits entries whose routes are not defined yet" do
      sign_in_as(create(:user))
      get feed_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('href="/"')
    end

    it "exposes the globe feed to members and no import leaf" do
      sign_in_as(create(:user))
      get feed_path

      expect(response.body).to include(%(href="#{feed_path}"), "ti-world")

      leaves = Allure::Navigation.sections.flat_map do |section|
        section.items.flat_map { |item| [ item.key, *item.items.map(&:key) ] }
      end
      expect(leaves).to include(:feed)
      expect(leaves).not_to include(:import)
    end
  end

  describe "calendar" do
    it "shows the activity calendar on /me for signed-in users with workouts" do
      user = create(:user)
      create(:workout, user:)
      sign_in_as(user)

      get me_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="calendar"')
      expect(response.body).to include("data-calendar-url-value=")
      expect(response.body).to include('data-calendar-week-start-value="monday"')
      expect(response.body).to include("data-calendar-day-url-value=")
      expect(response.body).to include('data-calendar-locale-value="fr"')
    end

    it "keeps the calendar off the feed" do
      user = create(:user)
      create(:workout, user:)
      sign_in_as(user)

      get feed_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-controller="calendar"')
    end

    it "carries the explanatory hint on the calendar card" do
      user = create(:user)
      create(:workout, user:)
      sign_in_as(user)

      get me_path

      button = Nokogiri::HTML(response.body).at_css('[data-controller="calendar"] .card-header [data-controller="tooltip"]')

      expect(button["data-bs-title"]).to include("Chaque case est un jour")
      expect(button["aria-label"]).to include("Chaque case est un jour")
    end

    it "keeps anonymous visitors out of the feed" do
      workout = create(:workout, title: "Public morning ride")
      create(:track_segment, workout:)
      profile = create(:publishing_profile, :without_endpoint_masks, user: workout.user)
      publish_workout!(user: workout.user, workout:, profile:)

      get feed_path

      expect(response).to redirect_to(new_session_path)
    end

    it "shows the calendar empty state with no workouts" do
      user = create(:user)
      sign_in_as(user)

      get me_path

      expect(response.body).to include('data-controller="calendar"')
      expect(response.body).to include("Aucune donnée")
    end
  end
end
