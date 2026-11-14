# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Segment leaderboards" do
  let(:sport) { create(:sport) }

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  def shared_segment(owner:, visibility:)
    create(:segment, user: owner, sport:, visibility:)
  end

  def listed_effort(segment:, athlete:, elapsed: 50, anonymous: false, sport: self.sport)
    workout = create(:workout, user: athlete, sport:)
    create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(athlete), status: "active")
    create(:segment_effort, segment:, workout:, user: athlete, sport:, elapsed_time: elapsed, moving_time: elapsed, anonymous:)
  end

  def follow(follower, followed)
    follower_actor = follower.reload.actor || create(:actor, :local, user: follower)
    followed_actor = followed.reload.actor || create(:actor, :local, user: followed)
    create(:following, :accepted, follower_actor:, followed_actor:)
  end

  describe "private visibility" do
    it "shows an empty board to the owner and 404s everyone else" do
      owner = create(:user)
      athlete = create(:user, display_name: "Athlète privé")
      segment = create(:segment, user: owner, sport:)
      listed_effort(segment:, athlete:)
      stranger = create(:user)

      get segment_leaderboard_path(segment)
      expect(response).to redirect_to(new_session_path)

      sign_in_as(owner)
      get segment_leaderboard_path(segment)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(athlete.display_name)

      sign_in_as(stranger)
      get segment_leaderboard_path(segment)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "followers_only visibility" do
    it "shows the listed rows to the owner's accepted followers, aliased unless followed, and 404s the others" do
      owner = create(:user)
      athlete = create(:user, display_name: "Athlete Alice")
      segment = shared_segment(owner:, visibility: "followers_only")
      listed_effort(segment:, athlete:)
      follower = create(:user)
      follow(follower, owner)
      stranger = create(:user)

      get segment_leaderboard_path(segment)
      expect(response).to redirect_to(new_session_path)

      sign_in_as(follower)
      get segment_leaderboard_path(segment)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(Allure::Leaderboard::Alias.for(user_id: athlete.id, segment_id: segment.id, locale: I18n.locale))
      expect(response.body).not_to include(athlete.display_name)

      create(:following, :accepted, follower_actor: follower.reload.actor,
                                    followed_actor: athlete.actor || create(:actor, :local, user: athlete))
      get segment_leaderboard_path(segment)
      expect(response.body).to include(athlete.display_name)

      sign_in_as(stranger)
      get segment_leaderboard_path(segment)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "board views" do
    it "narrows the board to the accounts the viewer follows" do
      owner = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      followed = create(:user, display_name: "Amie suivie")
      other = create(:user, display_name: "Inconnu")
      listed_effort(segment:, athlete: followed, elapsed: 60)
      listed_effort(segment:, athlete: other, elapsed: 50)
      viewer = create(:user)
      follow(viewer, followed)
      other_alias = Allure::Leaderboard::Alias.for(user_id: other.id, segment_id: segment.id, locale: I18n.locale)

      sign_in_as(viewer)
      get segment_leaderboard_path(segment)
      expect(response.body).to include("Amie suivie", other_alias, I18n.t("segments.leaderboard.scopes.following"))

      get segment_leaderboard_path(segment, board: "following")
      expect(response.body).to include("Amie suivie")
      expect(response.body).not_to include(other_alias)
      expect(response.body).to match(/class="nav-link active"[^>]*aria-current="true"[^>]*>#{I18n.t("segments.leaderboard.scopes.following")}/)

      get segment_path(segment, board: "following")
      expect(response.body).to include("Amie suivie")
      expect(response.body).not_to include(other_alias)
    end

    it "tells the athlete who sees them, or why nobody does" do
      owner = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      athlete = create(:user)
      workout = create(:workout, user: athlete, sport:)
      create(:segment_effort, segment:, workout:, user: athlete, sport:)

      sign_in_as(athlete)
      get segment_path(segment)
      expect(response.parsed_body.text).to include(I18n.t("segments.listing.reach.unpublished"), I18n.t("segments.listing.reach_hint.unpublished"))
      # The reach line is the §10.4 badge: the cut mark under the badge's own
      # grey while nobody reads the passage (DESIGN.md §20.6).
      reach = response.parsed_body.at_css("p [data-audience-state]")
      expect(reach["class"]).to include("allure-badge-responsive", "bg-secondary-lt")
      expect(reach.at_css(".ti-broadcast-off")).to be_present
      expect(reach.at_css(".allure-badge-responsive__label").text).to eq(I18n.t("segments.listing.reach.unpublished"))

      profile = public_publishing_profile_for(athlete)
      profile.update!(settings: profile.settings.merge("route" => false))
      create(:workout_publication, workout:, publishing_profile: profile, status: "active")
      get segment_path(segment)
      expect(response.parsed_body.text).to include(I18n.t("segments.listing.reach_hint.route_hidden"))
      expect(response.parsed_body.at_css("p [data-audience-state='public']")).to be_nil
    end
  end

  describe "category view" do
    let(:owner) { create(:user) }
    let(:segment) { shared_segment(owner:, visibility: "public") }
    let(:viewer) { create(:user) }

    def athletes(category, count, start: 10)
      Array.new(count) do |index|
        create(:user, leaderboard_category: category).tap do |athlete|
          listed_effort(segment:, athlete:, elapsed: start + index)
        end
      end
    end

    def nav_labels
      response.parsed_body.css("nav[aria-label='#{I18n.t('segments.leaderboard.categories.label')}'] a").map { it.text.strip }
    end

    it "offers only the categories with at least three athletes the viewer sees" do
      athletes("women", 3)
      athletes("men", 2, start: 5)

      sign_in_as(viewer)
      get segment_leaderboard_path(segment)

      expect(nav_labels).to eq([ I18n.t("segments.leaderboard.categories.all"), I18n.t("segments.leaderboard.categories.women") ])
    end

    it "hides the switch while no category reaches the threshold" do
      athletes("women", 2)

      sign_in_as(viewer)
      get segment_leaderboard_path(segment)

      expect(nav_labels).to be_empty
    end

    it "ranks the category among itself and keeps aliases" do
      men = athletes("men", 1, start: 1)
      women = athletes("women", 3, start: 20)
      man_alias = Allure::Leaderboard::Alias.for(user_id: men.first.id, segment_id: segment.id, locale: I18n.locale)
      first_woman = women.first

      sign_in_as(viewer)
      get segment_leaderboard_path(segment, category: "women")

      rows = response.parsed_body.css("table tbody tr")
      expect(rows.size).to eq(3)
      expect(response.body).not_to include(man_alias)
      expect(rows.first.text).to include(Allure::Leaderboard::Alias.for(user_id: first_woman.id, segment_id: segment.id, locale: I18n.locale))
      expect(response.body).not_to include(first_woman.username, profile_path(first_woman.username))
    end

    it "says a section is below the threshold instead of listing it" do
      athletes("women", 2)

      sign_in_as(viewer)
      get segment_leaderboard_path(segment, category: "women")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.css("table tbody tr")).to be_empty
      expect(response.parsed_body.text).to include(I18n.t("segments.leaderboard.categories.below_threshold", count: 3))
    end

    it "ignores an unknown category" do
      athletes("women", 3)

      sign_in_as(viewer)
      get segment_leaderboard_path(segment, category: "unspecified")

      expect(response.parsed_body.css("table tbody tr").size).to eq(3)
    end

    it "combines with the following view" do
      women = athletes("women", 3)
      women.each { follow(viewer, it) }
      athletes("women", 1, start: 1)

      sign_in_as(viewer)
      get segment_leaderboard_path(segment, board: "following", category: "women")

      expect(response.parsed_body.css("table tbody tr").size).to eq(3)
      expect(response.body).to include(*women.map(&:display_name))
    end

    it "adds the category rank under « Mon rang » for a declared athlete" do
      athletes("women", 2, start: 5)
      viewer.update!(leaderboard_category: "women")
      listed_effort(segment:, athlete: viewer, elapsed: 30)
      athletes("men", 1, start: 1)

      sign_in_as(viewer)
      get segment_path(segment)

      expect(response.parsed_body.at_css(".allure-metric-caption").text).to eq(
        I18n.t("segments.details.category_rank", rank: 3, total: 3, category: I18n.t("segments.leaderboard.categories.women"))
      )

      viewer.update!(leaderboard_category: "unspecified")
      get segment_path(segment)
      expect(response.parsed_body.at_css(".allure-metric-caption")).to be_nil
    end
  end

  describe "public visibility" do
    it "shows a pseudonymous board to signed-in strangers and the full board to the owner" do
      owner = create(:user)
      athlete = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      effort = listed_effort(segment:, athlete:)
      stranger = create(:user)
      expected_alias = Allure::Leaderboard::Alias.for(user_id: athlete.id, segment_id: segment.id, locale: I18n.locale)
      expected_month = I18n.l(effort.started_at.in_time_zone(Time.zone).to_date, format: :month_year)

      sign_in_as(stranger)
      get segment_leaderboard_path(segment)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(expected_alias, expected_month)
      expect(response.body).not_to include(athlete.username, profile_path(athlete.username))

      sign_in_as(owner)
      get segment_leaderboard_path(segment)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(athlete.display_name)
      expect(response.body).not_to include(expected_alias)
    end

    it "keeps anonymous rows aliased for the owner too" do
      owner = create(:user, display_name: "Propriétaire")
      athlete = create(:user, display_name: "Athlète anonyme")
      segment = shared_segment(owner:, visibility: "public")
      listed_effort(segment:, athlete:, anonymous: true)
      expected_alias = Allure::Leaderboard::Alias.for(user_id: athlete.id, segment_id: segment.id, locale: I18n.locale)

      sign_in_as(owner)
      get segment_leaderboard_path(segment)

      expect(response.body).to include(expected_alias)
      expect(response.body).not_to include(athlete.display_name)
    end
  end

  describe "creator attribution" do
    it "names the segment's creator and links to their profile" do
      owner = create(:user, display_name: "Créateur du segment")
      segment = shared_segment(owner:, visibility: "public")
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)

      expect(response.body).to include("Créateur du segment", "@#{owner.username}", profile_path(owner.username))
    end
  end

  describe "anonymous rows" do
    it "leaks no ShortUUID, profile path, username, or exact timestamp" do
      owner = create(:user)
      athlete = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      effort = listed_effort(segment:, athlete:, anonymous: true)
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(effort.to_param)
      expect(response.body).not_to include(effort.workout.to_param)
      expect(response.body).not_to include(profile_path(athlete.username))
      expect(response.body).not_to include(athlete.username)
      expect(response.body).not_to include(effort.started_at.iso8601)
      expect(response.body).to include(
        Allure::Leaderboard::Alias.for(user_id: athlete.id, segment_id: segment.id, locale: I18n.locale)
      )
      expect(response.body).to include("18,0 km/h")
    end
  end

  describe "pace and speed" do
    it "shows the stored average speed of a speed sport" do
      owner = create(:user)
      athlete = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      listed_effort(segment:, athlete:)
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)

      expect(response.body).to include(%(<th scope="col" class="text-end">Vitesse</th>), "18,0 km/h")
    end

    it "shows the stored average pace of a pace sport" do
      owner = create(:user)
      athlete = create(:user)
      running = create(:sport, pace_speed_display: "pace")
      segment = create(:segment, user: owner, sport: running, visibility: "public")
      listed_effort(segment:, athlete:, sport: running)
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)

      expect(response.body).to include(%(<th scope="col" class="text-end">Allure</th>), "3:20 /km")
    end
  end

  describe "ranking" do
    it "shows each athlete's best effort only" do
      owner = create(:user)
      athlete = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      listed_effort(segment:, athlete:, elapsed: 300)
      listed_effort(segment:, athlete:, elapsed: 40)
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("0:40")
      expect(response.body).not_to include("5:00")
    end

    it "renders medals for the top three and the numeral from fourth place" do
      owner = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      [ 60, 70, 80, 90 ].each { |elapsed| listed_effort(segment:, athlete: create(:user), elapsed:) }
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)

      expect(response.body).to include("allure-medal--gold", "allure-medal--silver", "allure-medal--bronze")
      rows = Nokogiri::HTML(response.body).css("table tbody tr")
      expect(rows.length).to eq(4)
      expect(rows[3].at_css("td [aria-hidden=true]").text).to eq("4")
      expect(rows[3].at_css("td .visually-hidden").text).to eq(I18n.t("medals.rank", rank: 4))
    end

    it "never shows an ineligible effort" do
      owner = create(:user)
      athlete = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      workout = create(:workout, user: athlete, sport:)
      create(:segment_effort, segment:, workout:, user: athlete, sport:, elapsed_time: 50)
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("0:50")
    end
  end

  describe "multi-sport segments" do
    it "renders one titled section per sport in catalog order" do
      owner = create(:user)
      cyclist = create(:sport)
      runner = create(:sport)
      segment = create(:segment, user: owner, sport: nil, visibility: "public")
      listed_effort(segment:, athlete: create(:user), sport: cyclist)
      listed_effort(segment:, athlete: create(:user), sport: runner)
      sign_in_as(owner)

      get segment_leaderboard_path(segment)

      expect(response.body).to include("#{segment.name} (#{cyclist.label})", "#{segment.name} (#{runner.label})")
      expect(response.body.index("(#{cyclist.label})")).to be < response.body.index("(#{runner.label})")
    end

    it "keeps a single plain section for a single-sport segment" do
      owner = create(:user)
      athlete = create(:user, display_name: "Athlète unique")
      segment = create(:segment, user: owner, sport:, visibility: "public")
      listed_effort(segment:, athlete:)
      sign_in_as(owner)

      get segment_leaderboard_path(segment)

      expect(response.body).to include(I18n.t("segments.leaderboard.title", name: segment.name), athlete.display_name)
      expect(response.body).not_to include("#{segment.name} (#{sport.label})")
    end

    it "labels each section's pace or speed column from its own sport" do
      owner = create(:user)
      cyclist = create(:sport)
      runner = create(:sport, pace_speed_display: "pace")
      segment = create(:segment, user: owner, sport: nil, visibility: "public")
      listed_effort(segment:, athlete: create(:user), sport: cyclist)
      listed_effort(segment:, athlete: create(:user), sport: runner)
      sign_in_as(owner)

      get segment_leaderboard_path(segment)

      expect(response.body).to include(%(<th scope="col" class="text-end">Vitesse</th>))
      expect(response.body).to include(%(<th scope="col" class="text-end">Allure</th>))
    end
  end

  describe "detail preview" do
    it "shows the top ten and links to the full board when a section overflows" do
      owner = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      11.times { |index| listed_effort(segment:, athlete: create(:user), elapsed: 50 + index) }
      sign_in_as(create(:user))

      get segment_path(segment)

      page = response.parsed_body
      expect(page.text).to include(I18n.t("segments.leaderboard.container_title"))
      expect(page.css("#classements table tbody tr").length).to eq(10)
      expect(page.at_css("#classements .card-header a[href='#{segment_leaderboard_path(segment)}']")&.text)
        .to eq(I18n.t("segments.leaderboard.view_all"))
    end

    it "omits the full-board link when every section fits" do
      owner = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      3.times { |index| listed_effort(segment:, athlete: create(:user), elapsed: 50 + index) }
      sign_in_as(create(:user))

      get segment_path(segment)

      page = response.parsed_body
      expect(page.css("#classements table tbody tr").length).to eq(3)
      expect(page.at_css("#classements a[href='#{segment_leaderboard_path(segment)}']")).to be_nil
    end

    it "renders one titled section per sport for an all-sports course" do
      owner = create(:user)
      cyclist = create(:sport)
      runner = create(:sport)
      segment = create(:segment, user: owner, sport: nil, visibility: "public")
      listed_effort(segment:, athlete: create(:user), sport: cyclist)
      listed_effort(segment:, athlete: create(:user), sport: runner)
      sign_in_as(create(:user))

      get segment_path(segment)

      expect(response.body).to include("#{segment.name} (#{cyclist.label})", "#{segment.name} (#{runner.label})")
    end

    it "shows the viewer's rank with the podium laurel on the details tile" do
      owner = create(:user)
      athlete = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      listed_effort(segment:, athlete:, elapsed: 60)
      sign_in_as(athlete)

      get segment_path(segment)

      page = response.parsed_body
      expect(page.text).to include(I18n.t("segments.details.ranking"), "1 / 1")
      expect(page.at_css(".allure-stamp--gold")).to be_present
      expect(page.at_css(".allure-metric-tile i.ti-laurel-wreath-1")).to be_present
    end

    it "marks an unlisted effort as not ranked on the details tile" do
      owner = create(:user)
      athlete = create(:user)
      segment = shared_segment(owner:, visibility: "public")
      create(:segment_effort, segment:, workout: create(:workout, user: athlete, sport:),
                              user: athlete, sport:, elapsed_time: 50)
      sign_in_as(athlete)

      get segment_path(segment)

      expect(response.body).to include(I18n.t("segments.listing.unranked"))
      expect(response.body).not_to include("allure-stamp--")
    end
  end
end
