# frozen_string_literal: true

require "rails_helper"

# M4 Slice 4 workout detail layout, revised for phones and the iOS companion:
# the map leads the page (the sticky left rail from `lg` up), the header menu
# carries the secondary actions including the original file and deletion, and
# below the grid come the comments, the sharing card — which lists what a
# profile shares instead of projecting it — and the participants.
RSpec.describe "Workout detail layout" do
  let(:owner) { create(:user) }
  let(:sport) { create(:sport) }

  it "renders the detail grid without a section nav" do
    workout = create(:workout, user: owner, sport:)
    create(:track_segment, workout:)
    sign_in_as(owner)

    get workout_path(workout)

    page = response.parsed_body
    expect(response.body).not_to include("allure-section-nav")

    layout = page.at_css(".allure-detail-layout--split")
    expect(layout).to be_present
    expect(layout.at_css(".allure-detail-before-map #section-summary")).to be_present
    expect(layout.at_css(".allure-detail-map #section-map")).to be_present
    expect(layout.at_css(".allure-detail-after-map #section-profile")).to be_present
    expect(layout.at_css("#section-sharing")).to be_nil
    # The map comes first in the document so it leads the phone layout.
    expect(layout.element_children.first["class"]).to include("allure-detail-map")

    fullwidth = page.at_css(".allure-detail-fullwidth")
    expect(fullwidth).to be_present
    expect(fullwidth.element_children.map { |child| child["id"] }).to eq(%w[section-photos section-sharing section-participants])
    expect(page.at_css("turbo-frame#workout-publication-preview")).to be_nil
    expect(page.at_css(".allure-danger-zone")).to be_nil
  end

  it "does not create an empty map rail for a map-only public page" do
    workout = create(:workout, user: owner, sport:)
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "description" => false, "metrics" => [], "mask_start" => false, "mask_finish" => false
      ))
    publish_workout!(user: owner, workout:, profile:)
    sign_in_as(create(:user))

    get workout_path(workout)

    page = response.parsed_body
    expect(page.at_css("#section-map")).to be_present
    expect(page.at_css(".allure-detail-layout--split")).to be_nil
  end

  it "withholds every owner section from a non-owner page" do
    workout = create(:workout, user: owner, sport:)
    create(:track_segment, workout:)
    create(:lap, workout:, number: 1)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publish_workout!(user: owner, workout:, profile:)
    sign_in_as(create(:user))

    get workout_path(workout)

    page = response.parsed_body
    expect(page.at_css("turbo-frame#workout-publication-preview")).to be_nil
    expect(page.at_css("#section-sharing")).to be_nil
    expect(page.at_css("#section-laps")).to be_nil
    expect(page.at_css("#section-participants")).to be_nil
    expect(page.at_css(".allure-danger-zone")).to be_nil
    # The full-width zone carries the thread every reader shares
    # (docs/dev/COMMENTS.md) and nothing of the owner's.
    expect(page.at_css(".allure-detail-fullwidth").element_children.map { |child| child["id"] }).to eq([ "comments" ])
  end

  describe "publication preview" do
    it "states exactly what the default profile would share" do
      workout = create(:workout, user: owner, sport:)
      create(:track_segment, workout:)
      sign_in_as(owner)

      get workout_path(workout)

      expect(response.body).to include("Voici exactement ce qui sera partagé")
      expect(response.body).to include("ne sont jamais partagés")
      expect(response.body).to include("Titre")
    end

    it "lists what the profile shares and leaves out, with live per-profile data" do
      workout = create(:workout, user: owner, sport:)
      create(:track_segment, workout:)
      sign_in_as(owner)

      get workout_path(workout)

      page = response.parsed_body
      shared = page.at_css('[data-publication-preview-target="shared"]')
      expect(shared.css("li").map { |item| item.text.strip }).to include(I18n.t("publishing_profiles.settings.title"))
      withheld = page.at_css('[data-publication-preview-target="withheld"]')
      expect(withheld.css("li").map { |item| item.text.strip }).to include(I18n.t("publishing_profiles.settings.device"))
      readiness = JSON.parse(page.at_css("form[data-publication-preview-readiness-value]")["data-publication-preview-readiness-value"])
      expect(readiness.values.first).to include("shared", "withheld")
      # No projection of the workout, no frame to load one.
      expect(response.body).not_to include("data-publication-preview-url-value")
    end
  end

  describe "summary" do
    it "counts only recorded extra metrics and names the missing ones once" do
      workout = create(:workout, user: owner, sport:, average_heart_rate: nil, max_heart_rate: nil,
                                 average_power: nil, max_power: nil)
      create(:track_segment, workout:)
      sign_in_as(owner)

      get workout_path(workout)

      summary = response.parsed_body.at_css("#section-summary")
      secondary = summary.css(".allure-secondary-metrics > div")
      expect(secondary.map { |item| item.at_css("dt").text.strip }).not_to include(I18n.t("workouts.show.metrics.average_heart_rate"))
      expect(summary.css(".allure-secondary-metrics dd").map(&:text)).not_to include("—")
      toggle = summary.at_css(".allure-disclosure-toggle")
      expect(toggle.text).to include(I18n.t("workouts.show.metrics.more", count: secondary.size))
      missing = summary.at_css(".allure-metrics-missing")
      expect(missing.text).to include(I18n.t("workouts.show.metrics.families.heart_rate"), I18n.t("workouts.show.metrics.families.power"))
      # The sentence folds with the extra metrics on phones.
      expect(missing["data-disclosure-target"]).to eq("content")
    end
  end

  describe "participants" do
    it "puts the invitation behind a header action and keeps the §19.20 sentence visible" do
      workout = create(:workout, user: owner, sport:)
      create(:track_segment, workout:)
      sign_in_as(owner)

      get workout_path(workout)

      card = response.parsed_body.at_css("#section-participants .card")
      expect(card.at_css(".card-header .card-actions button[data-bs-target='#workout-participation-invite']").text)
        .to include(I18n.t("workouts.participations.add"))
      expect(card.at_css("form#workout-participation-invite.collapse")).to be_present
      expect(card.at_css(".card-body > .form-text").text).to include(I18n.t("workouts.participations.invite_hint"))
      expect(response.parsed_body.css("#section-participants").size).to eq(1)
    end
  end

  describe "published edit notice" do
    it "warns that edits do not update the publication, only when published" do
      draft = create(:workout, user: owner, sport:)
      published = create(:workout, user: owner, sport:)
      create(:track_segment, workout: published)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      publish_workout!(user: owner, workout: published, profile:)
      sign_in_as(owner)

      get edit_workout_path(published)
      expect(response.body).to include(I18n.t("workouts.edit.published_notice"))

      get edit_workout_path(draft)
      expect(response.body).not_to include(I18n.t("workouts.edit.published_notice"))
    end
  end

  describe "elevation chart equivalent" do
    it "renders a data table and hides the canvas from assistive tech" do
      workout = create(:workout, user: owner, sport:)
      create(:track_segment, workout:)
      sign_in_as(owner)

      get workout_path(workout)

      expect(response.body).to include("Voir les données")
      expect(response.body).to include("<table", "100", "112")
      expect(response.body).to include('data-elevation-chart-target="chart" aria-hidden="true"')
    end
  end

  describe "action hierarchy" do
    it "keeps publication in sharing and exposes download and deletion in the menu too" do
      workout = create(:workout, user: owner, sport:)
      create(:track_segment, workout:)
      workout.original_file.attach(io: StringIO.new("gpx"), filename: "route.gpx", content_type: "application/gpx+xml")
      sign_in_as(owner)

      get workout_path(workout)

      page = response.parsed_body
      header = page.at_css(".allure-workout-header")
      expect(header.at_css("a[href='#section-sharing']")).to be_present
      expect(page.at_css("#section-sharing form[action='#{publish_workout_path(workout)}']")).to be_present

      expect(header.at_css(".dropdown-menu a[href='#{workout_original_file_path(workout)}']")).to be_present
      expect(header.at_css(".dropdown-menu form[action='#{workout_path(workout)}']")).to be_present
      # The menu is the only place for both: no original-data card, no danger zone.
      expect(page.css("a[href='#{workout_original_file_path(workout)}']").size).to eq(1)
      expect(page.css("form[action='#{workout_path(workout)}'] input[name='_method'][value='delete']").size).to eq(1)
    end
  end

  describe "identity header" do
    it "leads with the sport tile and title, the sport and date under it, then the places and badges" do
      workout = create(:workout, user: owner, sport:, title: "Sortie du matin",
                                 places: [ { "name" => "Valmorin" }, { "name" => "Cimefroide" } ])
      create(:track_segment, workout:)
      sign_in_as(owner)

      get workout_path(workout)

      header = response.parsed_body.at_css(".allure-workout-header")
      identity = header.at_css(".allure-workout-header__identity")
      expect(identity.at_css(".sport-tile.avatar-md")).to be_present
      expect(identity.at_css("h1.page-title").text).to include("Sortie du matin")
      expect(identity.text).not_to include(I18n.t("workouts.show.by_author_html", author: owner.display_name))

      expect(identity.at_css(".allure-workout-header__when").text).to include(sport.label)

      metadata = header.at_css(".page-pretitle")
      expect(metadata.at_css(".sport-tile")).to be_nil
      expect(metadata.at_css('[data-audience-state="unpublished"]').text).to include(I18n.t("workouts.publication.unpublished"))
      # Publish and the ⋯ menu share the title's row.
      expect(header.at_css(".allure-workout-header__top .allure-workout-header__actions a[href='#section-sharing']")).to be_present

      places = header.at_css(".allure-workout-header__places")
      expect(places.at_css(".ti-map-pin")).to be_present
      expect(places.text).to include("Valmorin · Cimefroide")
    end

    it "puts another account's author line under the title and withholds the places" do
      workout = create(:workout, user: owner, sport:, title: "Sortie du matin",
                                 places: [ { "name" => "Valmorin" } ])
      create(:track_segment, workout:)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      publish_workout!(user: owner, workout:, profile:)
      sign_in_as(create(:user))

      get workout_path(workout)

      header = response.parsed_body.at_css(".allure-workout-header")
      identity = header.at_css(".allure-workout-header__identity")
      expect(identity.at_css(".sport-tile.avatar-md")).to be_present
      expect(identity.at_css("h1 + .text-secondary").text).to include(owner.display_name)
      expect(header.at_css(".allure-workout-header__places")).to be_nil
    end
  end
end
