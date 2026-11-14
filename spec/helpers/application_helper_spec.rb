# frozen_string_literal: true

require "rails_helper"

# DESIGN.md §9.5/§6.5: a person's avatar is Tabler's default circle (no shape
# class), while sport tiles and non-person marks are `avatar-square`.
RSpec.describe ApplicationHelper do
  def avatar_classes(html, selector = ".avatar")
    Nokogiri::HTML.fragment(html).at_css(selector)["class"].split
  end

  describe "#avatar_tag" do
    it "overlays the highest tier with a bounded colour, without changing avatar bytes", :funding do
      user = create(:user, funding_badge_color: "teal")
      create(:funding_contribution, :energy, user:)
      html = Nokogiri::HTML.fragment(helper.avatar_tag(user, decorative: false))
      expect(html.at_css(".funding-badge--teal .ti-bolt")).to be_present
      expect(html.at_css("svg.avatar")["aria-label"]).to include(I18n.t("funding.badge.label"))
      user.update!(funding_badge_hidden: true)
      expect(helper.avatar_tag(user)).not_to include("funding-badge")
    end

    it "keeps the badge in companion HTML but never shows it when disabled", :funding do
      user = create(:user)
      create(:funding_contribution, user:)
      allow(helper.request).to receive(:user_agent).and_return("Allure iOS Hotwire Native")
      expect(helper.avatar_tag(user)).to include("funding-badge")
      ENV["FUNDING_ENABLED"] = "false"
      expect(helper.avatar_tag(user)).not_to include("funding-badge")
    end

    it "renders the generated art on Tabler's default circle" do
      user = build(:user, username: "alpine", display_name: "Alpine Skier")

      classes = avatar_classes(helper.avatar_tag(user), "svg.avatar")

      expect(classes).to include("avatar", "avatar-md")
      expect(classes).not_to include("rounded", "avatar-square")
    end

    it "hides the generated art from assistive tech when decorative and labels it otherwise" do
      user = build(:user, display_name: "Alpine Skier")
      decorative = Nokogiri::HTML.fragment(helper.avatar_tag(user)).at_css("svg.avatar")
      labelled = Nokogiri::HTML.fragment(helper.avatar_tag(user, decorative: false)).at_css("svg.avatar")

      expect(decorative["aria-hidden"]).to eq("true")
      expect(decorative["role"]).to be_nil
      expect(labelled["role"]).to eq("img")
      expect(labelled["aria-label"]).to eq("Alpine Skier")
    end

    it "prefers an uploaded avatar over the generated art" do
      user = create(:user)
      user.avatar.attach(io: StringIO.new("uploaded"), filename: "avatar.webp", content_type: "image/webp")

      image = Nokogiri::HTML.fragment(helper.avatar_tag(user)).at_css("img.avatar")

      expect(image["src"]).to eq(profile_avatar_path(user.username))
      expect(image["alt"]).to eq("")
    end

    it "renders the cached image on the same circle" do
      user = create(:user, gravatar_opt_in: true)
      user.gravatar_cache.attach(
        io: StringIO.new("cached-avatar"), filename: "gravatar.jpg", content_type: "image/jpeg"
      )

      classes = avatar_classes(helper.avatar_tag(user), "img.avatar")

      expect(classes).to include("avatar", "avatar-md")
      expect(classes).not_to include("rounded", "avatar-square")
    end

    describe "the operator badge (DESIGN.md §9.7)" do
      around do |example|
        previous = ENV["INSTANCE_OPERATOR_USERNAME"]
        ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
        example.run
      ensure
        previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
      end

      it "overlays user-shield for the operator, without any funding contribution" do
        operator = create(:user, username: "operator")
        html = Nokogiri::HTML.fragment(helper.avatar_tag(operator, decorative: false))

        expect(html.at_css(".operator-badge .ti-user-shield")).to be_present
        expect(html.at_css(".funding-badge")).to be_nil
        expect(html.at_css("svg.avatar")["aria-label"]).to include(I18n.t("operator.badge.label"))
      end

      it "coexists with the supporter badge and names both", :funding do
        operator = create(:user, username: "operator")
        create(:funding_contribution, user: operator)
        html = Nokogiri::HTML.fragment(helper.avatar_tag(operator, decorative: false))

        expect(html.at_css(".operator-badge .ti-user-shield")).to be_present
        expect(html.at_css(".funding-badge")).to be_present
        label = html.at_css("svg.avatar")["aria-label"]
        expect(label).to include(I18n.t("operator.badge.label"), I18n.t("funding.badge.label"))
      end

      it "is absent for an ordinary account and for a deactivated operator" do
        expect(helper.avatar_tag(create(:user))).not_to include("operator-badge")

        operator = create(:user, username: "operator")
        operator.update!(suspended_at: Time.current)
        expect(helper.avatar_tag(operator)).not_to include("operator-badge")
      end
    end
  end

  describe "#actor_avatar_tag" do
    it "renders a remote actor on the same circle" do
      actor = build(:actor, display_name: "Marie", handle: "marie")

      classes = avatar_classes(helper.actor_avatar_tag(actor), "svg.avatar")

      expect(classes).to include("avatar", "avatar-md")
      expect(classes).not_to include("rounded", "avatar-square")
    end

    it "renders a local actor through its account's avatar chain" do
      actor = build(:actor, :local)
      actor.user.avatar.attach(io: StringIO.new("uploaded"), filename: "avatar.webp", content_type: "image/webp")

      image = Nokogiri::HTML.fragment(helper.actor_avatar_tag(actor)).at_css("img.avatar")

      expect(image["src"]).to eq(profile_avatar_path(actor.user.username))
    end

    it "renders the same generated art for a local actor and its account" do
      actor = build(:actor, :local)
      actor_svg = Nokogiri::HTML.fragment(helper.actor_avatar_tag(actor)).at_css("svg.avatar")
      user_svg = Nokogiri::HTML.fragment(helper.avatar_tag(actor.user)).at_css("svg.avatar")

      expect(actor_svg.to_html).to eq(user_svg.to_html)
    end
  end

  describe "#sport_tile_tag" do
    it "renders the tile as a Tabler avatar-square" do
      sport = build(:sport, slug: "running", colour_group: "run")

      classes = avatar_classes(helper.sport_tile_tag(sport), ".sport-tile")

      expect(classes).to include("avatar", "avatar-square", "avatar-md")
      expect(classes).not_to include("rounded")
    end

    it "carries the label as an accessible, tooltipped mark instead of a native title" do
      sport = build(:sport, slug: "running", colour_group: "run")

      tile = Nokogiri::HTML.fragment(helper.sport_tile_tag(sport, label: "Course")).at_css(".sport-tile")

      expect(tile["aria-label"]).to eq("Course")
      expect(tile["data-controller"]).to eq("tooltip")
      expect(tile["data-bs-title"]).to eq("Course")
      expect(tile["title"]).to be_nil
    end
  end

  describe "#tooltip_data" do
    it "returns the shared Bootstrap tooltip data with no native title" do
      expect(helper.tooltip_data("Voir")).to eq(
        controller: "tooltip", bs_toggle: "tooltip", bs_title: "Voir"
      )
    end

    it "gates the tooltip on a media query when the label is printed alongside it" do
      expect(helper.tooltip_data("Public", media: "(max-width: 767.98px)")).to eq(
        controller: "tooltip", bs_toggle: "tooltip", bs_title: "Public",
        tooltip_media_value: "(max-width: 767.98px)"
      )
    end
  end

  describe "#route_image_tag" do
    let(:options) { { class: "card-img-top", alt: "Parcours" } }
    let(:light_url) { "/workouts/1/route_image" }
    let(:dark_url) { "/workouts/1/route_image?theme=dark" }

    def route_image_theme=(value)
      user = build(:user, route_image_theme: value)
      helper.define_singleton_method(:current_user) { user }
    end

    def page_theme=(value)
      helper.define_singleton_method(:current_theme) { value }
    end

    it "paints the light variant and arms the live swap in auto mode" do
      self.route_image_theme = "auto"
      self.page_theme = "light"

      fragment = Nokogiri::HTML.fragment(helper.route_image_tag(light_url:, dark_url:, **options))
      image = fragment.at_css("img")

      expect(fragment.at_css("picture")).to be_nil
      expect(image["src"]).to eq(light_url)
      expect(image["data-controller"]).to eq("route-image")
      expect(image["data-route-image-light-url-value"]).to eq(light_url)
      expect(image["data-route-image-dark-url-value"]).to eq(dark_url)
      expect(image["data-action"]).to eq("allure:theme-changed@window->route-image#themeChanged")
      expect(image["class"]).to eq("card-img-top")
      expect(image["alt"]).to eq("Parcours")
    end

    it "paints the dark variant on a dark page in auto mode" do
      self.route_image_theme = "auto"
      self.page_theme = "dark"

      fragment = Nokogiri::HTML.fragment(helper.route_image_tag(light_url:, dark_url:, **options))
      image = fragment.at_css("img")

      expect(image["src"]).to eq(dark_url)
      expect(image["data-route-image-light-url-value"]).to eq(light_url)
      expect(image["data-route-image-dark-url-value"]).to eq(dark_url)
    end

    it "renders a plain light image when light is forced" do
      self.route_image_theme = "light"

      fragment = Nokogiri::HTML.fragment(helper.route_image_tag(light_url:, dark_url:, **options))
      image = fragment.at_css("img")

      expect(fragment.at_css("picture")).to be_nil
      expect(image["src"]).to eq(light_url)
      expect(image["data-controller"]).to be_nil
    end

    it "renders a plain dark image when dark is forced" do
      self.route_image_theme = "dark"

      fragment = Nokogiri::HTML.fragment(helper.route_image_tag(light_url:, dark_url:, **options))
      image = fragment.at_css("img")

      expect(fragment.at_css("picture")).to be_nil
      expect(image["src"]).to eq(dark_url)
      expect(image["data-controller"]).to be_nil
    end
  end

  describe "#virtual_basemap_for" do
    let(:virtual_sport) { catalog_sport("cycling_virtual") }
    let(:road_sport) { catalog_sport("cycling_road") }

    def workout(sport, longitude:, latitude:)
      point = RGeo::Geographic.spherical_factory(srid: 4326).point(longitude, latitude)
      build(:workout, sport:, start_point: point, bounds: [ latitude, longitude, latitude, longitude ])
    end

    # The world images are not committed (PLAN_VIRTUAL.md §2.1), so the helper
    # examples stub the catalogue lookup and assert the arguments it receives;
    # the lookup itself is covered in platforms_spec.
    def stub_world_map(longitude:, latitude:)
      basemap = Allure::Virtual::Basemap.new(
        image: "virtual_worlds/zwift/watopia-f4991742.webp",
        bounds: [ 166.87747, -11.74087, 167.03255, -11.62597 ],
        background: "#0884e2"
      )
      expect(Allure::Virtual::Platforms).to receive(:basemap_at)
        .with(longitude:, latitude:, public_root: Rails.public_path)
        .and_return(basemap)
      basemap
    end

    it "returns the world map of a virtual activity inside its world" do
      basemap = stub_world_map(longitude: 166.95251, latitude: -11.63555)

      expect(helper.virtual_basemap_for(workout(virtual_sport, longitude: 166.95251, latitude: -11.63555)))
        .to eq(basemap)
    end

    it "keeps the world map when the recording starts just outside the published image" do
      # A new area of the same world: outside the image rectangle, inside the
      # radius that recognises the world.
      basemap = stub_world_map(longitude: 166.955, latitude: -11.62)

      expect(helper.virtual_basemap_for(workout(virtual_sport, longitude: 166.955, latitude: -11.62)))
        .to eq(basemap)
    end

    it "keeps the ordinary basemap for a virtual world the catalogue does not know" do
      expect(helper.virtual_basemap_for(workout(virtual_sport, longitude: 0, latitude: 0))).to be_nil
    end

    it "never claims a real-world activity, even where a world sits on the same city" do
      # Zwift's London rectangle covers real London.
      expect(helper.virtual_basemap_for(workout(road_sport, longitude: -0.11655, latitude: 51.49815))).to be_nil
    end

    it "keeps the ordinary basemap when the profile turned it off" do
      display = workout(virtual_sport, longitude: 166.95251, latitude: -11.63555)

      expect(helper.virtual_basemap_for(display, basemap: false)).to be_nil
    end

    it "reads the world from a sanitized track when there is no recorded start" do
      display = double(
        sport: virtual_sport,
        track: { "features" => [ { "geometry" => { "coordinates" => [ [ 166.95251, -11.63555 ] ] } } ] }
      )
      basemap = stub_world_map(longitude: 166.95251, latitude: -11.63555)

      expect(helper.virtual_basemap_for(display)).to eq(basemap)
    end

    it "is nil without geometry or for a sport that does not draw a world" do
      expect(helper.virtual_basemap_for(build(:workout, sport: virtual_sport, start_point: nil, bounds: nil))).to be_nil
      expect(helper.virtual_basemap_for(double(sport: nil))).to be_nil
    end
  end

  describe "#basemap_theme" do
    def account(route_image_theme)
      user = route_image_theme && build(:user, route_image_theme:)
      helper.define_singleton_method(:current_user) { user }
    end

    def page_theme=(value)
      helper.define_singleton_method(:current_theme) { value }
    end

    it "follows the page theme in auto mode and without an account" do
      self.page_theme = "dark"

      account("auto")
      expect([ helper.basemap_theme_preference, helper.basemap_theme ]).to eq(%w[auto dark])

      account(nil)
      expect([ helper.basemap_theme_preference, helper.basemap_theme ]).to eq(%w[auto dark])
    end

    it "forces the chosen variant whatever the page theme" do
      self.page_theme = "dark"
      account("light")
      expect([ helper.basemap_theme_preference, helper.basemap_theme ]).to eq(%w[light light])

      self.page_theme = "light"
      account("dark")
      expect([ helper.basemap_theme_preference, helper.basemap_theme ]).to eq(%w[dark dark])
    end
  end
end
