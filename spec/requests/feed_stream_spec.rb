# frozen_string_literal: true

require "rails_helper"

# The signed-in stream at /feed: followed accounts and entitled remote notes by
# default, with the instance's public publications joining through the
# URL-driven Public switch. The anonymous surface lives in feed_spec.rb.
RSpec.describe "Feed stream" do
  let(:viewer) { create(:user) }
  let(:viewer_actor) { Federation::ActorProvisioner.new(user: viewer).call! }
  let(:followed) { create(:user, username: "followed") }
  let(:followed_actor) { Federation::ActorProvisioner.new(user: followed).call! }
  let(:stranger) { create(:user, username: "stranger") }
  let(:remote_author) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      handle: "demo@remote.example",
      acct: "demo@remote.example",
      display_name: "Demo Remote"
    )
  end

  def local_workout(user:, published_at:, title: nil)
    workout = create(:workout, user:, title:)
    PublishingProfile.ensure_built_ins_for!(user)
    profile = user.publishing_profiles.find_by!(built_in_key: "public")
    create(
      :workout_publication, workout:, publishing_profile: profile, published_at:,
      representation: {
        "title" => title.presence || "Workout",
        "sport_slug" => workout.sport.slug,
        "started_at" => workout.started_at.iso8601,
        "metrics" => {}
      }
    )
    workout
  end

  def followers_workout(user:, published_at:, title: nil)
    workout = create(:workout, user:, title:)
    PublishingProfile.ensure_built_ins_for!(user)
    profile = user.publishing_profiles.find_by!(built_in_key: "followers")
    create(
      :workout_publication, workout:, publishing_profile: profile, published_at:,
      representation: {
        "title" => title.presence || "Workout",
        "sport_slug" => workout.sport.slug,
        "started_at" => workout.started_at.iso8601,
        "metrics" => {}
      }
    )
    workout
  end

  def entitled_note(published_at:, recipient: viewer_actor, title: "Remote hike")
    note = create(:remote_note, actor: remote_author, published_at:, title:, representation: {
      "title" => title, "sport_label" => "Hiking", "started_at" => published_at.iso8601, "metrics" => {}
    })
    create(:remote_note_recipient, remote_note: note, recipient_actor: recipient)
    note
  end

  it "redirects the old following address to the feed" do
    get following_path

    expect(response).to redirect_to(feed_path)
  end

  describe "with follows" do
    before do
      create(:following, :accepted, follower_actor: viewer_actor, followed_actor: followed_actor)
    end

    it "shows followed publications and entitled remote notes with Public off" do
      local_workout(user: followed, published_at: 2.hours.ago, title: "Followed ride")
      entitled_note(published_at: 1.hour.ago)
      local_workout(user: stranger, published_at: 30.minutes.ago, title: "Stranger ride")
      sign_in_as(viewer)

      get feed_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Followed ride", "Remote hike")
      expect(response.body).not_to include("Stranger ride")
      expect(response.parsed_body.at_css("#feed-public")["checked"]).to be_nil
    end

    it "shows a followed author's followers publication to the follower" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      followers_workout(user: followed, published_at: 1.hour.ago, title: "Follower-only ride")
      sign_in_as(viewer)

      get feed_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Follower-only ride")
    end

    it "shows a followed author's followers publication while the restricted audience is disabled" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      followers_workout(user: followed, published_at: 1.hour.ago, title: "Follower-only ride")
      sign_in_as(viewer)

      get feed_path

      expect(response.body).to include("Follower-only ride")
    end

    it "never shows another account's followers publication" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      followers_workout(user: stranger, published_at: 1.hour.ago, title: "Stranger followers ride")
      sign_in_as(viewer)

      get feed_path

      expect(response.body).not_to include("Stranger followers ride")
    end

    it "always shows the viewer's own publications, whatever the audience" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      local_workout(user: viewer, published_at: 2.hours.ago, title: "My public ride")
      followers_workout(user: viewer, published_at: 1.hour.ago, title: "My followers ride")
      sign_in_as(viewer)

      get feed_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My public ride", "My followers ride", I18n.t("feed.you"))
      expect(response.parsed_body.css("article.card").length).to eq(2)
      expect(response.parsed_body.at_css("#feed-public")["checked"]).to be_nil
    end

    it "points the viewer's own followers publication at the browser media endpoint" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      workout = followers_workout(user: viewer, published_at: 1.hour.ago, title: "My followers ride")
      publication = workout.active_publications.first
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("\x89PNG\r\n\x1A\nroute".b),
        filename: "sanitized.png",
        content_type: "image/png"
      )
      publication.attach_sanitized_route_image!(blob)
      sign_in_as(viewer)

      get feed_path

      expect(response.body).to include(publication_route_image_path(publication))
      expect(response.body).not_to include(workout_publication_route_image_path(publication))
    end

    it "does not duplicate the viewer's own publication when Public is on" do
      local_workout(user: viewer, published_at: 2.hours.ago, title: "My public ride")
      local_workout(user: stranger, published_at: 1.hour.ago, title: "Stranger ride")
      sign_in_as(viewer)

      get feed_path(public: 1)

      expect(response.parsed_body.css("article.card").length).to eq(2)
      expect(response.parsed_body.css("article.card").text.scan("My public ride").length).to eq(1)
    end

    it "adds the instance public publications when Public is on, without duplicating a followed author" do
      local_workout(user: followed, published_at: 2.hours.ago, title: "Followed ride")
      local_workout(user: stranger, published_at: 30.minutes.ago, title: "Stranger ride")
      sign_in_as(viewer)

      get feed_path(public: 1)

      expect(response.body).to include("Followed ride", "Stranger ride")
      expect(response.parsed_body.css("article.card").length).to eq(2)
      expect(response.parsed_body.at_css("#feed-public")["checked"]).to eq("checked")
    end

    it "carries an explicit Public off value when the switch is unchecked" do
      sign_in_as(viewer)

      get feed_path(public: 1)

      hidden = response.parsed_body.at_css('input[type="hidden"][name="public"]')
      expect(hidden["value"]).to eq("0")
      expect(response.parsed_body.at_css("#feed-public")["checked"]).to eq("checked")
    end

    it "keeps the import action out of the feed header" do
      sign_in_as(viewer)

      get feed_path

      header = response.parsed_body.at_css(".page-header")
      expect(header.at_css(%(a[href="#{new_workout_import_path}"]))).to be_nil
    end

    it "renders the Public info tooltip without a visible Apply button" do
      sign_in_as(viewer)

      get feed_path

      tooltip = response.parsed_body.at_css('button[data-controller="tooltip"]')
      expect(tooltip["aria-label"]).to eq(I18n.t("feed.public.hint"))
      expect(tooltip["data-bs-title"]).to eq(I18n.t("feed.public.hint"))
      expect(response.parsed_body.at_css('noscript input[type="submit"]')).to be_present
    end

    it "shows the neutral empty state when followed accounts published nothing" do
      sign_in_as(viewer)

      get feed_path

      expect(response.body).to include(I18n.t("feed.nothing.title"))
      expect(response.body).not_to include(I18n.t("feed.no_follows.title"))
    end

    it "removes a remote author's notes when the viewer unfollows" do
      following = create(:following, :accepted, follower_actor: viewer_actor, followed_actor: remote_author)
      note = entitled_note(published_at: 1.hour.ago)
      sign_in_as(viewer)

      get feed_path
      expect(response.body).to include("Remote hike")

      resolver = instance_double(Federation::ActorResolver, resolve: remote_author)
      Federation::Unfollow.new(user: viewer, target: remote_author.uri, actor_resolver: resolver).call!

      get feed_path
      expect(response.body).not_to include("Remote hike")
      expect(note.entitled_to?(viewer_actor)).to be(false)
      expect(following.reload).to be_undone
    end

    it "keeps an item listed when its media failed" do
      note = entitled_note(published_at: 1.hour.ago)
      create(:remote_note_attachment, remote_note: note, kind: "gpx", status: "unavailable")
      sign_in_as(viewer)

      get feed_path

      expect(response.body).to include("Remote hike")
    end

    it "wires the next page into the infinite-scroll sentinel, preserving the Public choice" do
      13.times { |index| local_workout(user: stranger, published_at: (index + 1).hours.ago, title: "Public #{index}") }
      sign_in_as(viewer)

      get feed_path(public: 1)

      expect(response.parsed_body.at_css('[data-infinite-scroll-target="items"]')).to be_present
      sentinel = response.parsed_body.at_css('[data-infinite-scroll-url-value]')
      expect(sentinel["data-infinite-scroll-url-value"]).to include("page=2", "public=1")
      expect(sentinel["data-infinite-scroll-dedupe-attribute-value"]).to eq("data-feed-day")

      skeleton = response.parsed_body.at_css('[data-infinite-scroll-target="skeleton"]')
      expect(skeleton.key?("hidden")).to be(true)
      expect(skeleton.at_css(".placeholder-glow .placeholder")).to be_present

      get feed_path(public: 1, page: 2)
      expect(response).to have_http_status(:ok)
    end

    it "omits the next-page skeleton at the end of the stream" do
      local_workout(user: stranger, published_at: 1.hour.ago, title: "Only public")
      sign_in_as(viewer)

      get feed_path(public: 1)

      expect(response.parsed_body.at_css('[data-infinite-scroll-target="skeleton"]')).to be_nil
    end
  end

  describe "without follows" do
    it "shows the instance public publications by default" do
      local_workout(user: stranger, published_at: 1.hour.ago, title: "Public ride")
      sign_in_as(viewer)

      get feed_path

      expect(response.body).to include("Public ride")
      expect(response.parsed_body.at_css("#feed-public")["checked"]).to eq("checked")
    end

    it "honors an explicit Public off and offers to find accounts" do
      local_workout(user: stranger, published_at: 1.hour.ago, title: "Public ride")
      sign_in_as(viewer)

      get feed_path(public: 0)

      expect(response.body).not_to include("Public ride")
      expect(response.body).to include(
        I18n.t("feed.no_follows.title"), I18n.t("feed.no_follows.hint"), people_path
      )
      expect(response.parsed_body.at_css("#feed-public")["checked"]).to be_nil
    end

    it "shows the public empty state when the instance published nothing" do
      sign_in_as(viewer)

      get feed_path

      expect(response.body).to include(I18n.t("feed.empty.title"), I18n.t("feed.empty.import"))
    end
  end
end
