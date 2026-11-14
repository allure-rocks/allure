# frozen_string_literal: true

require "rails_helper"

# The segment index list (DESIGN.md §20.6): one row per course with its
# glyph, name and place, sport, facts, mini profile, the board's record under
# the alias rules and the viewer's own best time; a sport filter, sortable
# columns and endless scroll. The discover page renders no list.
RSpec.describe "Segment index list" do
  let(:viewer) { create(:user) }
  let(:sport) { create(:sport) }

  def run!(segment, user:, elapsed: 120, eligible: true, effort_sport: nil)
    workout = create(:workout, user:, sport: effort_sport || segment.sport || sport)
    if eligible
      create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(user), status: "active")
    end
    create(
      :segment_effort,
      segment:,
      workout:,
      user:,
      sport: workout.sport,
      elapsed_time: elapsed,
      moving_time: elapsed - 5
    )
  end

  def row_names
    Nokogiri::HTML(response.body).css("table.allure-segment-table tbody tr .allure-table-title a").map(&:text)
  end

  it "renders a row with the glyph, place, facts, mini profile and the owner's badges" do
    create(
      :segment, user: viewer, sport:, name: "Côte de la Citadelle", visibility: "private",
                place_name: "Rochelune", place_status: "ready", distance: 1_800.0, ascent: 112.0, average_grade: 6.2,
                elevation_profile: [ { "d" => 0.0, "ele" => 120.0 }, { "d" => 900.0, "ele" => 180.0 },
                                     { "d" => 1_800.0, "ele" => 232.0 } ]
    )
    sign_in_as(viewer)

    get segments_path

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    row = page.at_css("table.allure-segment-table tbody tr")
    expect(row.text).to include("Côte de la Citadelle", "Rochelune", "1,8", "112", "6,2")
    expect(row.at_css("svg.allure-segment-thumbnail path")["d"]).to start_with("M")
    expect(row.at_css("svg.allure-segment-sparkline")["aria-label"]).to include("120", "232")
    expect(row.text).to include(I18n.t("segments.card.mine"), I18n.t("segments.visibility.private"))
    mine = row.at_css("[data-badge='mine']")
    expect(mine["class"]).to include("bg-primary-lt", "allure-badge-responsive")
    expect(mine.at_css(".ti-user-circle")).to be_present
    # The phone row carries the same responsive badge, not a hand-made icon pill.
    expect(page.at_css("ul.allure-segment-list [data-badge='mine'].allure-badge-responsive")).to be_present
    expect(page.css("ul.allure-segment-list li").size).to eq(1)
    expect(response.body).not_to include("allure-segment-card", "card-img-top")
  end

  it "leads a descending course with its descent and a negative grade, and sorts grades by steepness" do
    create(:segment, user: viewer, sport:, name: "Descente du Galibier", distance: 1_000.0,
                     ascent: 0.0, descent: 90.0, average_grade: -9.0)
    create(:segment, user: viewer, sport:, name: "Faux plat", distance: 1_000.0,
                     ascent: 20.0, descent: 0.0, average_grade: 2.0)
    sign_in_as(viewer)

    get segments_path(sort: "grade_desc")

    expect(row_names).to eq([ "Descente du Galibier", "Faux plat" ])
    row = Nokogiri::HTML(response.body).at_css("table.allure-segment-table tbody tr")
    expect(row.text.squish).to include(I18n.t("segments.index.table.descent_label"), "90", "-9,0")
    expect(row.at_css(".ti-trending-down")).to be_present
  end

  it "shows another owner's record under an alias and the viewer's own best with their standing" do
    owner = create(:user, display_name: "Paul Créateur")
    segment = create(:segment, user: owner, sport:, visibility: "public", name: "Col partagé")
    other = create(:user, display_name: "Marie Grimpeuse")
    run!(segment, user: other, elapsed: 90)
    run!(segment, user: viewer, elapsed: 200)
    sign_in_as(viewer)

    get segments_path

    alias_name = Allure::Leaderboard::Alias.for(user_id: other.id, segment_id: segment.id, locale: I18n.locale)
    row = Nokogiri::HTML(response.body).at_css("table.allure-segment-table tbody tr")
    expect(row.text).to include("Col partagé", alias_name, "1:30", "3:20")
    expect(row.to_html).to include("allure-medal--gold", "/ 2")
    expect(response.body).not_to include("Marie Grimpeuse")
    expect(row.text).not_to include(I18n.t("segments.card.mine"))
  end

  it "names every athlete on the owner's own public board" do
    segment = create(:segment, user: viewer, sport:, visibility: "public")
    other = create(:user)
    run!(segment, user: other, elapsed: 90)
    sign_in_as(viewer)

    get segments_path

    expect(response.body).to include(other.display_name)
    expect(response.body).not_to include(
      Allure::Leaderboard::Alias.for(user_id: other.id, segment_id: segment.id, locale: I18n.locale)
    )
  end

  it "has no record on a private course but shows the owner's personal best" do
    segment = create(:segment, user: viewer, sport:, name: "Ma boucle privée")
    run!(segment, user: viewer, elapsed: 125, eligible: false)
    sign_in_as(viewer)

    get segments_path

    cells = Nokogiri::HTML(response.body).css("table.allure-segment-table tbody tr td.text-end").map { it.text.squish }
    expect(cells.last(2)).to eq([ "—", "2:05" ])
    expect(response.body).not_to include("allure-medal--gold")
  end

  it "filters by sport and keeps the all-sports courses under every sport" do
    other_sport = create(:sport)
    create(:segment, user: viewer, sport:, name: "Course du sport")
    create(:segment, user: viewer, sport: other_sport, name: "Course de l'autre sport")
    create(:segment, user: viewer, sport: nil, name: "Course tous sports")
    sign_in_as(viewer)

    get segments_path(sports: [ sport.id ])

    expect(row_names).to contain_exactly("Course du sport", "Course tous sports")
    expect(response.body).to include("segment_sport_filter_#{sport.id}", "segment_sport_filter_#{other_sport.id}")
  end

  it "lists an all-sports course once per sport it was run in, each with its own record and best" do
    ride = create(:sport)
    segment = create(:segment, user: viewer, sport: nil, visibility: "public", name: "Citadelle")
    other = create(:user)
    run!(segment, user: other, elapsed: 390, effort_sport: ride)
    run!(segment, user: other, elapsed: 737, effort_sport: sport)
    run!(segment, user: viewer, elapsed: 433, effort_sport: ride)
    create(:segment, user: viewer, sport: nil, name: "Jamais parcouru")
    sign_in_as(viewer)

    get segments_path(sort: "record_asc")

    ride_title = I18n.t("segments.leaderboard.sport_title", name: "Citadelle", sport: ride.label)
    run_title = I18n.t("segments.leaderboard.sport_title", name: "Citadelle", sport: sport.label)
    expect(row_names).to eq([ ride_title, run_title, "Jamais parcouru" ])
    rows = Nokogiri::HTML(response.body).css("table.allure-segment-table tbody tr").map { it.text.squish }
    expect(rows[0]).to include("6:30", "7:13")
    expect(rows[1]).to include("12:17")
    expect(rows[1]).not_to include("7:13")
    expect(Nokogiri::HTML(response.body).css("ul.allure-segment-list li").size).to eq(3)

    get segments_path(sports: [ sport.id ])
    expect(row_names).to contain_exactly(run_title, "Jamais parcouru")
    expect(response.body).to include("segment_sport_filter_#{ride.id}")
  end

  it "sorts by a column, keeps missing values last, and keeps the kind in the header links" do
    create(:segment, user: viewer, sport:, name: "Bravo", distance: 2_000.0, ascent: nil, descent: nil)
    create(:segment, user: viewer, sport:, name: "alpha", distance: 3_000.0, ascent: 50.0)
    create(:segment, user: viewer, sport:, name: "Charlie", distance: 1_000.0, ascent: 10.0)
    sign_in_as(viewer)

    get segments_path(sort: "name_asc")
    expect(row_names).to eq(%w[alpha Bravo Charlie])

    get segments_path(sort: "distance_desc")
    expect(row_names).to eq(%w[alpha Bravo Charlie])

    # The elevation column sorts by the leading figure, a descent's included.
    create(:segment, user: viewer, sport:, name: "Delta", distance: 1_500.0, ascent: 5.0, descent: 80.0)

    get segments_path(sort: "ascent_asc")
    expect(row_names).to eq(%w[Charlie alpha Delta Bravo])

    get segments_path(sort: "ascent_desc")
    expect(row_names).to eq(%w[Delta alpha Charlie Bravo])

    create(:segment, :route, user: viewer, sport:)
    get segments_path(kind: "route", sort: "bogus")
    hrefs = Nokogiri::HTML(response.body).css("th.allure-sort-cell a").map { it["href"] }
    expect(hrefs).to include(segments_path(kind: "route", sort: "name_asc"), segments_path(kind: "route", sort: "best_asc"))
    # Routes are never shared: no board, so no record column nor record sort.
    expect(hrefs).not_to include(segments_path(kind: "route", sort: "record_asc"))
    expect(response.body).not_to include("value=\"record_asc\"")
  end

  it "sorts by the board's record and by the viewer's own best" do
    fast = create(:segment, user: viewer, sport:, visibility: "public", name: "Rapide")
    slow = create(:segment, user: viewer, sport:, visibility: "public", name: "Lent")
    create(:segment, user: viewer, sport:, visibility: "public", name: "Vierge")
    other = create(:user)
    run!(fast, user: other, elapsed: 60)
    run!(slow, user: other, elapsed: 600)
    # The viewer's own efforts are not published: they count for « Mon RP »,
    # never for the board's record.
    run!(fast, user: viewer, elapsed: 900, eligible: false)
    run!(slow, user: viewer, elapsed: 30, eligible: false)
    sign_in_as(viewer)

    get segments_path(sort: "record_asc")
    expect(row_names).to eq(%w[Rapide Lent Vierge])

    get segments_path(sort: "record_desc")
    expect(row_names).to eq(%w[Lent Rapide Vierge])

    get segments_path(sort: "best_asc")
    expect(row_names).to eq(%w[Lent Rapide Vierge])
  end

  it "reads the record from the board the viewer sees" do
    with_restricted_federation do
      owner = create(:user)
      segment = create(:segment, user: owner, sport:, visibility: "public", name: "Col partagé")
      athlete = create(:user, display_name: "Athlète abonnés")
      workout = create(:workout, user: athlete, sport:)
      create(:workout_publication, workout:, status: "active",
                                   publishing_profile: create(:publishing_profile, :followers, user: athlete))
      create(:segment_effort, segment:, workout:, user: athlete, sport:, elapsed_time: 90, moving_time: 85)
      follower = create(:user)
      create(:following, :accepted, follower_actor: create(:actor, :local, user: follower),
                                    followed_actor: athlete.reload.actor || create(:actor, :local, user: athlete))

      sign_in_as(viewer)
      get segments_path
      expect(Nokogiri::HTML(response.body).at_css("table.allure-segment-table tbody tr").text).not_to include("1:30")

      sign_in_as(follower)
      get segments_path
      row = Nokogiri::HTML(response.body).at_css("table.allure-segment-table tbody tr")
      expect(row.text).to include("1:30", "Athlète abonnés")
    end
  end

  def with_restricted_federation
    original = ENV["FEDERATION_RESTRICTED_ENABLED"]
    ENV["FEDERATION_RESTRICTED_ENABLED"] = "true"
    yield
  ensure
    ENV["FEDERATION_RESTRICTED_ENABLED"] = original
  end

  it "scrolls endlessly: the next page URL keeps the filter and sort" do
    create_list(:segment, 21, user: viewer, sport:)
    sign_in_as(viewer)

    get segments_path(sort: "name_asc", sports: [ sport.id ])

    wrapper = Nokogiri::HTML(response.body).at_css("[data-controller='infinite-scroll']")
    next_url = wrapper["data-infinite-scroll-url-value"]
    expect(next_url).to include("page=2", "sort=name_asc", "sports")
    expect(row_names.size).to eq(20)

    get next_url
    expect(row_names.size).to eq(1)
    expect(Nokogiri::HTML(response.body).at_css("[data-controller='infinite-scroll']")["data-infinite-scroll-url-value"]).to eq("")
  end
end
