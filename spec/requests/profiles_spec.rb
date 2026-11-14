# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public profiles" do
  let(:owner) { create(:user) }

  # A sanitized snapshot, independent from later edits of the source workout.
  def followers_representation(workout, distance:)
    {
      "title" => workout.title,
      "sport_slug" => workout.sport.slug,
      "started_at" => workout.started_at.iso8601(6),
      "metrics" => { "distance" => distance }
    }
  end

  it "renders only public publication snapshots while restricted federation is disabled" do
    public_workout = create(:workout, user: owner, title: "Publication title", distance: 1_000)
    create(:track_segment, workout: public_workout)
    public_profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publish_workout!(user: owner, workout: public_workout, profile: public_profile)

    followers_workout = create(:workout, user: owner, title: "Followers secret")
    create(:workout_publication, :with_followers, workout: followers_workout)
    public_workout.update!(title: "Private source title", distance: 9_000)

    sign_in_as(owner)
    get profile_path(owner.username)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Publication title")
    expect(response.body).not_to include("Private source title", "Followers secret", "9,0 km")
    expect(response.parsed_body.at_css(".allure-feed-metrics")).to be_nil
  end

  it "keeps the profile editorial even when the snapshot includes performances and records" do
    workout = create(:workout, user: owner, title: "Sortie record")
    create(
      :workout_publication, workout:,
      representation: followers_representation(workout, distance: 1_000)
        .merge("record_types" => [ "FD" ], "record_distances" => [ "km5" ])
    )

    sign_in_as(create(:user))
    get profile_path(owner.username)

    card = response.parsed_body.at_css("article.feed-item")
    expect(card.at_css(".feed-item__author, .allure-record-badge, .ti-trophy, .allure-feed-metrics")).to be_nil
    expect(card.at_css("h3 a.stretched-link")["href"]).to eq(workout_path(workout))
    expect(card.text).not_to include("1,0 km")
  end

  it "shows a followed owner's followers publication to an accepted local follower" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    owner_actor = Federation::ActorProvisioner.new(user: owner).call!
    workout = create(:workout, user: owner, title: "Sortie entre abonnés")
    create(
      :workout_publication, :with_followers, workout:, actor: owner_actor,
      representation: followers_representation(workout, distance: 1_000)
    )

    follower = create(:user)
    follower_actor = Federation::ActorProvisioner.new(user: follower).call!
    create(:following, :accepted, follower_actor:, followed_actor: owner_actor)

    sign_in_as(follower)
    get profile_path(owner.username)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Sortie entre abonnés",
      I18n.t("workouts.publication.audience.followers")
    )
  end

  it "shows the owner their own followers publication while restricted federation is enabled" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    workout = create(:workout, user: owner, title: "Sortie entre abonnés")
    create(
      :workout_publication, :with_followers, workout:,
      representation: followers_representation(workout, distance: 1_000)
    )

    sign_in_as(owner)
    get profile_path(owner.username)

    expect(response.body).to include("Sortie entre abonnés", I18n.t("workouts.publication.audience.followers"))
  end

  it "hides a followers publication from a pending follower" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    owner_actor = Federation::ActorProvisioner.new(user: owner).call!
    workout = create(:workout, user: owner, title: "Sortie entre abonnés")
    create(:workout_publication, :with_followers, workout:, actor: owner_actor)

    follower = create(:user)
    follower_actor = Federation::ActorProvisioner.new(user: follower).call!
    create(:following, follower_actor:, followed_actor: owner_actor)

    sign_in_as(follower)
    get profile_path(owner.username)

    expect(response.body).not_to include("Sortie entre abonnés")
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("profile.empty.title")))
  end

  it "hides a followers publication from an unrelated member while restricted federation is enabled" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    workout = create(:workout, user: owner, title: "Sortie entre abonnés")
    create(:workout_publication, :with_followers, workout:)

    sign_in_as(create(:user))
    get profile_path(owner.username)

    expect(response.body).not_to include("Sortie entre abonnés")
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("profile.empty.title")))
  end

  it "hides a followers publication from an accepted follower while restricted federation is disabled" do
    owner_actor = Federation::ActorProvisioner.new(user: owner).call!
    workout = create(:workout, user: owner, title: "Sortie entre abonnés")
    create(:workout_publication, :with_followers, workout:, actor: owner_actor)

    follower = create(:user)
    follower_actor = Federation::ActorProvisioner.new(user: follower).call!
    create(:following, :accepted, follower_actor:, followed_actor: owner_actor)

    sign_in_as(follower)
    get profile_path(owner.username)

    expect(response.body).not_to include("Sortie entre abonnés")
  end

  it "uses the signed-in account's locale on an unauthenticated-access page" do
    sign_in_as(create(:user, locale: "en"))

    get profile_path(owner.username)

    expect(response.body).to include('lang="en"')
  end

  it "counts sports in SQL without loading every snapshot or summing performances" do
    catalog_sport("running")
    catalog_sport("cycling")
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    started_at = Time.current.iso8601(6)
    [
      { "sport_slug" => "running", "started_at" => started_at, "metrics" => { "distance" => 1_500 } },
      { "sport_slug" => "running", "started_at" => started_at, "metrics" => { "distance" => 2_500 } },
      { "sport_slug" => "cycling", "started_at" => started_at, "metrics" => {} }
    ].each do |representation|
      create(
        :workout_publication,
        workout: create(:workout, user: owner),
        publishing_profile: profile,
        representation: representation
      )
    end

    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
    sign_in_as(create(:user))
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get profile_path(owner.username)
    end

    expect(response).to have_http_status(:ok)
    chart = response.parsed_body.at_css('[data-hub-pie-payload-value]')
    payload = JSON.parse(chart["data-hub-pie-payload-value"])
    expect(payload["slices"].map { |slice| slice["values"] }).to eq([ { "workouts" => 2 }, { "workouts" => 1 } ])
    expect(chart["data-hub-pie-metric-value"]).to eq("workouts")
    expect(chart.css('input[name="mix_metric"], select.hub-mix-metric-select')).to be_empty
    expect(response.body).not_to include("4,0 km")
    expect(queries).to include(a_string_matching(/GROUP BY workout_publications.representation ->> 'sport_slug'/))
    expect(queries).not_to include(a_string_matching(/SUM\(/))
    expect(queries).not_to include(a_string_matching(/\ASELECT "workout_publications"\."representation" FROM/))
  end

  it "does not let reserved URL options escape into pagination links" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    13.times do
      create(:workout_publication, workout: create(:workout, user: owner), publishing_profile: profile)
    end
    sign_in_as(create(:user))

    get profile_path(owner.username), params: { host: %(evil.example"><script>alert(1)</script>) }

    expect(response).to have_http_status(:ok)
    links = response.parsed_body.css(".pagination a.page-link").map { |link| link["href"] }
    expect(links).to be_present
    expect(links).to all(start_with("/"))
    expect(response.body).not_to include(%(evil.example"><script>alert(1)</script>))
  end

  it "shows a pending local request with cancellation and no retry" do
    viewer = create(:user, username: "marie")
    create(:user, username: "paul")
    sign_in_as(viewer)

    post federation_follow_path, params: { target: "paul" }

    get profile_path("paul")

    expect(response.body).to include(
      I18n.t("follows.states.pending"), I18n.t("follows.actions.cancel_request")
    )
    expect(response.body).not_to include(I18n.t("follows.actions.retry"))
  end

  it "offers editing only on one's own profile and omits an empty biography" do
    owner.update!(bio: nil)
    sign_in_as(owner)

    get profile_path(owner.username)

    page = response.parsed_body
    expect(page.at_css("a[href='#{settings_profile_path}']").text).to include(I18n.t("profile.edit"))
    expect(page.at_css(".profile-about")).to be_nil

    sign_in_as(create(:user))
    get profile_path(owner.username)

    expect(response.parsed_body.css("a").map(&:text)).not_to include(I18n.t("profile.edit"))
  end

  it "keeps local biographies as escaped text while preserving paragraph breaks" do
    owner.update!(bio: "Bonjour <b>tout le monde</b>\n\nDeuxième paragraphe.")
    sign_in_as(create(:user))

    get profile_path(owner.username)

    bio = response.parsed_body.at_css(".profile-bio")
    expect(bio.text).to include("Bonjour <b>tout le monde</b>", "Deuxième paragraphe.")
    expect(bio.css("p").size).to eq(2)
    expect(bio.at_css("b")).to be_nil
  end

  it "preserves the published story and social controls without the device line" do
    workout = create(:workout, user: owner)
    create(:workout_publication, workout:, representation: followers_representation(workout, distance: 1_000).merge(
      "description" => "Le récit de cette sortie.", "device" => "Private performance computer"
    ))
    sign_in_as(create(:user))

    get profile_path(owner.username)

    card = response.parsed_body.at_css("article.feed-item")
    expect(card.text).to include("Le récit de cette sortie.")
    expect(card.at_css(".allure-reactions")).to be_present
    expect(card.text).not_to include("Private performance computer")
  end

  it "preserves sport and period filters in endless-scroll and fallback pagination" do
    sport = catalog_sport("running")
    profile = create(:publishing_profile, user: owner)
    13.times do |index|
      workout = create(:workout, user: owner, sport:, title: "Journal #{index}", started_at: 1.day.ago)
      create(:workout_publication, workout:, publishing_profile: profile, representation: followers_representation(workout, distance: 1_000))
    end
    sign_in_as(create(:user))

    get profile_path(owner.username), params: { sport: "running", period: "days30" }

    page = response.parsed_body
    loader = page.at_css('[data-controller="infinite-scroll"]')
    query = Rack::Utils.parse_nested_query(URI.parse(loader["data-infinite-scroll-url-value"]).query)
    expect(query).to include("sport" => "running", "period" => "days30", "page" => "2")
    expect(page.css("article.feed-item").size).to eq(12)
    expect(page.css(".allure-feed-metrics, .allure-record-badge")).to be_empty
    expect(response.body).to include("<noscript>", "pagination")

    get loader["data-infinite-scroll-url-value"]
    expect(response.parsed_body.css("article.feed-item").size).to eq(1)
  end

  it "distinguishes a filtered-empty journal from a profile without visible publications" do
    workout = create(:workout, user: owner, started_at: 2.years.ago)
    create(:workout_publication, workout:)
    sign_in_as(create(:user))

    get profile_path(owner.username), params: { period: "days30" }

    expect(response.parsed_body.at_css(".empty-title").text).to eq(I18n.t("profile.filtered_empty.title"))
    clear = response.parsed_body.css("a").find { |link| link.text == I18n.t("profile.filters.clear") }
    expect(clear["href"]).to eq(profile_path(owner.username))
  end
end
