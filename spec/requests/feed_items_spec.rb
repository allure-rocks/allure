# frozen_string_literal: true

require "rails_helper"

# The feed card (DESIGN.md §8.3, §20.1): one anatomy for local publications
# and received notes, the day separators, the visitor intro, and the
# privacy negatives a card must keep. The stream composition itself lives in
# feed_stream_spec.rb.
RSpec.describe "Feed items" do
  include ActiveSupport::Testing::TimeHelpers

  let(:viewer) { create(:user, username: "viewer") }
  let(:viewer_actor) { Federation::ActorProvisioner.new(user: viewer).call! }
  let(:author) { create(:user, username: "marie", display_name: "Marie Dufour") }
  let(:cycling) { catalog_sport("cycling") }
  let(:remote_author) do
    create(:actor, uri: "https://remote.example/users/demo", handle: "demo@remote.example",
                   acct: "demo@remote.example", display_name: "Demo Remote")
  end

  def publish(workout, published_at: 1.hour.ago, representation: {}, settings: {})
    PublishingProfile.ensure_built_ins_for!(workout.user)
    profile = workout.user.publishing_profiles.find_by!(built_in_key: "public")
    profile.update!(settings: profile.settings.merge(settings)) if settings.any?
    create(:workout_publication, workout:, publishing_profile: profile, published_at:,
                                 representation: {
                                   "title" => workout.title, "sport_slug" => workout.sport.slug,
                                   "started_at" => workout.started_at.iso8601, "metrics" => {}
                                 }.merge(representation))
  end

  def local_item(title: "Sortie du matin", published_at: 1.hour.ago, representation: {}, settings: {}, user: author)
    workout = create(:workout, user:, sport: cycling, title:)
    publish(workout, published_at:, representation:, settings:)
    workout
  end

  def remote_item(title: "Remote hike", published_at: 1.hour.ago, **attributes)
    note = create(:remote_note, actor: remote_author, published_at:, title:, **attributes)
    create(:remote_note_recipient, remote_note: note, recipient_actor: viewer_actor)
    note
  end

  def follow!(followed)
    create(:following, :accepted, follower_actor: viewer_actor, followed_actor: Federation::ActorProvisioner.new(user: followed).call!)
  end

  def cards = response.parsed_body.css("article.feed-item")

  describe "the shared card" do
    it "renders a local publication and a received note through one anatomy, without a button" do
      workout = local_item
      note = remote_item
      sign_in_as(viewer)

      get feed_path(public: 1)

      expect(cards.length).to eq(2)
      cards.each do |card|
        expect(card.at_css(".feed-item__author")).to be_present
        expect(card.at_css("h3 a.stretched-link")).to be_present
        expect(card.css(".btn")).to be_empty
      end
      hrefs = cards.map { |card| card.at_css("h3 a.stretched-link")["href"] }
      expect(hrefs).to contain_exactly(workout_path(workout), remote_note_path(note))
    end

    it "labels the card link and links the sport tile with a tooltip" do
      workout = local_item(title: "Distinct title")
      remote_item(title: "Remote title")
      sign_in_as(viewer)

      get feed_path(public: 1)

      labels = cards.map { |card| card.at_css("h3 a.stretched-link")["aria-label"] }
      expect(labels).to contain_exactly("#{I18n.t('workouts.show.title')} : Distinct title",
                                        "#{I18n.t('remote_notes.open')} : Remote title")
      tile = cards.find { |card| card.text.include?("Distinct title") }.at_css("a.sport-tile--link")
      expect(tile["href"]).to eq(workout_path(workout))
      expect(tile["aria-label"]).to eq(I18n.t("sports.cycling"))
      expect(tile["data-controller"]).to eq("tooltip")
    end

    it "names a local author by username and a remote author by instance" do
      local_item
      remote_item
      sign_in_as(viewer)

      get feed_path(public: 1)

      local = cards.find { |card| card.text.include?("Marie Dufour") }
      expect(local.at_css(".feed-item__author").text).to include("@marie")
      expect(local.css(".feed-item__author a.feed-item__link").map { |a| a["href"] }.uniq).to eq([ profile_path("marie") ])
      expect(local.text).not_to include(I18n.t("feed.remote_badge"))

      remote = cards.find { |card| card.text.include?("Demo Remote") }
      expect(remote.at_css(".feed-item__author").text).to include("@demo@remote.example", I18n.t("feed.remote_badge"))
      expect(remote.css(".feed-item__author a.feed-item__link").map { |a| a["href"] }.uniq).to eq([ remote_profile_path("demo@remote.example") ])
    end

    it "badges only the viewer's own publications" do
      local_item(user: viewer, title: "Mine")
      local_item(title: "Theirs")
      sign_in_as(viewer)

      get feed_path(public: 1)

      mine = cards.find { |card| card.text.include?("Mine") }
      theirs = cards.find { |card| card.text.include?("Theirs") }
      expect(mine.at_css(".feed-item__author").text).to include(I18n.t("feed.you"), I18n.t("workouts.publication.audience.public"))
      you = mine.at_css(".feed-item__author [data-badge='mine']")
      expect(you["class"]).to include("bg-primary-lt")
      expect(you.at_css(".ti-user-circle")).to be_present
      expect(theirs.at_css(".feed-item__author").text).not_to include(I18n.t("feed.you"))
    end
  end

  describe "metric tiles" do
    it "renders the four primary tiles in order and keeps secondary metrics off the card" do
      local_item(representation: { "metrics" => {
        "distance" => 12_000, "moving_time" => 3600, "average_speed" => 3.3, "ascent" => 180, "max_heart_rate" => 170
      } })
      sign_in_as(viewer)

      get feed_path(public: 1)

      tiles = cards.first.css(".allure-feed-metrics .allure-metric-tile")
      expect(tiles.map { |tile| tile.at_css("dt").text }).to eq([
        I18n.t("workouts.show.metrics.distance"), I18n.t("workouts.show.metrics.moving_time"),
        I18n.t("workouts.show.metrics.average_speed"), I18n.t("workouts.show.metrics.ascent")
      ])
      expect(tiles.map { |tile| tile.at_css("dd").text.squish }).to eq([ "12,0 km", "1:00:00", "11,9 km/h", "180 m" ])
      expect(tiles.first.at_css("dd small").text).to eq("km")
      expect(cards.first.text).not_to include(I18n.t("workouts.show.metrics.max_heart_rate"))
    end

    it "gives a withheld metric no tile at all" do
      local_item(representation: { "metrics" => { "distance" => 12_000 } })
      sign_in_as(viewer)

      get feed_path(public: 1)

      expect(cards.first.css(".allure-metric-tile").length).to eq(1)
      expect(cards.first.text).not_to include(I18n.t("workouts.show.metrics.ascent"), "—")
    end

    it "renders no tile row when the snapshot carries no metric" do
      local_item(representation: { "metrics" => {} })
      sign_in_as(viewer)

      get feed_path(public: 1)

      expect(cards.first.at_css("dl")).to be_nil
    end

    it "stamps the record tile and names the record in the badge" do
      local_item(representation: { "metrics" => { "distance" => 12_000 }, "record_types" => [ "FD" ] })
      sign_in_as(viewer)

      get feed_path(public: 1)

      card = cards.first
      expect(card.at_css(".allure-metric-tile .card-stamp .ti-trophy")).to be_present
      expect(card.at_css(".allure-metric-tile .visually-hidden").text).to include(I18n.t("records.types.fd"))
      expect(card.at_css(".feed-item__lift .allure-record-badge")["aria-label"]).to include(I18n.t("records.types.fd"))
    end
  end

  describe "published content" do
    it "shows an escaped, bounded description excerpt and never the remote HTML" do
      local_item(representation: { "description" => "<b>Bold</b> & long " + ("mot " * 200) })
      remote_item(description: "Remote words", content_html: "<p>Remote <em>markup</em></p>")
      sign_in_as(viewer)

      get feed_path(public: 1)

      excerpts = cards.map { |card| card.at_css(".feed-item__excerpt") }
      local = excerpts.find { |excerpt| excerpt.text.include?("Bold") }
      expect(local.inner_html).to include("&lt;b&gt;Bold&lt;/b&gt; &amp; long")
      expect(local.text.length).to be <= 300
      expect(local.text).to end_with("…")
      expect(response.body).not_to include("<b>Bold</b>", "<em>markup</em>")
      expect(excerpts.find { |excerpt| excerpt.text.include?("Remote words") }).to be_present
    end

    it "shows the device only when the snapshot carries one" do
      local_item(title: "With device", representation: { "device" => "Garmin Edge 540" })
      local_item(title: "Without device")
      sign_in_as(viewer)

      get feed_path(public: 1)

      with = cards.find { |card| card.text.include?("With device") }
      without = cards.find { |card| card.text.include?("Without device") }
      expect(with.at_css(".ti-device-watch")).to be_present
      expect(with.text).to include("Garmin Edge 540")
      expect(without.at_css(".ti-device-watch")).to be_nil
    end

    it "shows the activity's smart date, not the publication instant" do
      travel_to(Time.find_zone("Europe/Paris").local(2026, 9, 16, 12)) do
        workout = create(:workout, user: author, sport: cycling, title: "Old ride",
                                   started_at: Time.find_zone("Europe/Paris").local(2026, 6, 1, 7, 30))
        publish(workout, published_at: 1.hour.ago)
        sign_in_as(viewer)

        get feed_path(public: 1)

        expect(cards.first.at_css(".allure-table-nums").text).to include("1 juin 07:30")
        expect(cards.first.at_css(".allure-table-nums").text).not_to include(I18n.t("workouts.dates.today"))
      end
    end
  end

  describe "media states" do
    it "shows the pending skeleton for a local image still rendering" do
      local_item(settings: { "route_image" => true })
      sign_in_as(viewer)

      get feed_path(public: 1)

      state = cards.first.at_css(".feed-item__media-state")
      expect(state["role"]).to eq("status")
      expect(state["class"]).to include("placeholder-glow")
      expect(state.text).to include(I18n.t("workouts.route_image.pending"))
    end

    it "shows the pending skeleton, the unavailable frame, or nothing for remote media" do
      pending = remote_item(title: "Pending image")
      create(:remote_note_attachment, remote_note: pending, kind: "route_image", status: "pending")
      failed = remote_item(title: "Failed image")
      create(:remote_note_attachment, remote_note: failed, kind: "route_image", status: "unavailable")
      gpx_only = remote_item(title: "GPX only")
      create(:remote_note_attachment, remote_note: gpx_only, kind: "gpx", status: "pending")
      sign_in_as(viewer)

      get feed_path

      pending_card = cards.find { |card| card.text.include?("Pending image") }
      expect(pending_card.at_css(".feed-item__media-state.placeholder-glow[role='status']").text).to include(I18n.t("workouts.route_image.pending"))
      failed_card = cards.find { |card| card.text.include?("Failed image") }
      expect(failed_card.at_css(".feed-item__media-state[role='status'] .ti-photo-off")).to be_present
      expect(failed_card.text).to include(I18n.t("remote_notes.media.unavailable"))
      expect(cards.find { |card| card.text.include?("GPX only") }.at_css(".feed-item__media-state")).to be_nil
    end
  end

  describe "day separators" do
    it "groups the stream by publication day in the viewer's zone" do
      travel_to(Time.find_zone("Europe/Paris").local(2026, 9, 16, 12)) do
        local_item(title: "Today one", published_at: 2.hours.ago)
        local_item(title: "Today two", published_at: 3.hours.ago)
        local_item(title: "Yesterday", published_at: 1.day.ago)
        local_item(title: "Last week", published_at: 5.days.ago)
        sign_in_as(viewer)

        get feed_path(public: 1)

        separators = response.parsed_body.css("h2.allure-list-separator")
        expect(separators.map { |h| h["data-feed-day"] }).to eq(%w[2026-09-16 2026-09-15 2026-09-11])
        expect(separators.map(&:text)).to eq([ "Aujourd'hui", "Hier", "vendredi 11 septembre" ])
        column = response.parsed_body.at_css('[data-infinite-scroll-target="items"]')
        expect(column.children.select(&:element?).first.name).to eq("h2")
      end
    end

    it "spells out the year for a publication of another year" do
      travel_to(Time.find_zone("Europe/Paris").local(2026, 9, 16, 12)) do
        local_item(title: "Old", published_at: Time.find_zone("Europe/Paris").local(2025, 12, 24, 10))
        sign_in_as(viewer)

        get feed_path(public: 1)

        expect(response.parsed_body.at_css("h2.allure-list-separator").text).to eq("mercredi 24 décembre 2025")
      end
    end

    it "follows the viewer's time zone across midnight" do
      viewer.update!(time_zone: "Pacific/Auckland")
      travel_to(Time.utc(2026, 9, 16, 12)) do
        local_item(title: "Late", published_at: Time.utc(2026, 9, 15, 23, 30))
        sign_in_as(viewer)

        get feed_path(public: 1)

        expect(response.parsed_body.at_css("h2.allure-list-separator")["data-feed-day"]).to eq("2026-09-16")
      end
    end

    it "opens the next page with a separator for the day the previous page ended on" do
      travel_to(Time.find_zone("Europe/Paris").local(2026, 9, 16, 12)) do
        13.times { |index| local_item(title: "Item #{index}", published_at: (index + 1).minutes.ago) }
        sign_in_as(viewer)

        get feed_path(public: 1, page: 2)

        column = response.parsed_body.at_css('[data-infinite-scroll-target="items"]')
        first = column.children.select(&:element?).first
        expect(first["data-feed-day"]).to eq("2026-09-16")
        expect(response.parsed_body.at_css("[data-infinite-scroll-dedupe-attribute-value]")["data-infinite-scroll-dedupe-attribute-value"]).to eq("data-feed-day")
      end
    end
  end

  describe "visitors" do
    it "redirects an anonymous visitor to sign-in before rendering any card" do
      local_item

      get feed_path

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "privacy" do
    it "leaks no coordinate, storage URL, remote URL or remote HTML" do
      local_item(representation: { "metrics" => { "distance" => 12_000 } })
      remote_item(content_html: "<p>Remote <em>markup</em></p>")
      sign_in_as(viewer)

      get feed_path(public: 1)

      expect(response.body).not_to include("6.4074", "45.071", "/rails/active_storage",
                                           "https://remote.example", "<em>markup</em>")
    end
  end

  describe "query cost" do
    # Eligibility scopes depend on the clock. Keep identical predicates (and
    # query-cache behaviour) across both requests when comparing list sizes.
    around { |example| freeze_time { example.run } }

    it "does not grow with the number of items" do
      follow!(author)
      local_item(title: "One")
      remote_item(title: "Two")
      sign_in_as(viewer)
      get feed_path(public: 1)
      small = count_queries { get feed_path(public: 1) }

      4.times { |index| local_item(title: "Local #{index}", user: create(:user)) }
      3.times { |index| remote_item(title: "Remote #{index}") }
      3.times { |index| local_item(title: "Followed #{index}") }
      large = count_queries { get feed_path(public: 1) }

      expect(cards.length).to eq(12)
      expect(large).to eq(small)
    end
  end
end
