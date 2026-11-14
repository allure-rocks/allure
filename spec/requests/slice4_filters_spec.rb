# frozen_string_literal: true

require "rails_helper"

# M4 Slice 4 proofs: workout list filtering, sorting, and view state live in
# URL parameters (§13), with chips, a live count, and distinct empty states.
RSpec.describe "Slice 4 workout filters" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:running) { catalog_sport("running") }
  let(:cycling) { catalog_sport("cycling") }

  before { sign_in_as(user) }

  it "filters by multiple sports" do
    create(:workout, user:, sport: running, title: "Kept run")
    create(:workout, user:, sport: cycling, title: "Hidden ride")

    get workouts_path, params: { sports: [ running.id.to_s ] }

    expect(response.body).to include("Kept run")
    expect(response.body).not_to include("Hidden ride")
    expect(response.body).to include("Course à pied")
  end

  it "filters by publication state" do
    published = create(:workout, user:, sport: running, title: "Published one")
    create(:track_segment, workout: published)
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    publish_workout!(user:, workout: published, profile:)
    create(:workout, user:, sport: running, title: "Draft one")

    get workouts_path, params: { publication: "published" }
    expect(response.body).to include("Published one")
    expect(response.body).not_to include("Draft one")

    get workouts_path, params: { publication: "not_published" }
    expect(response.body).to include("Draft one")
    expect(response.body).not_to include("Published one")
  end

  it "filters by commute" do
    create(:workout, user:, sport: cycling, title: "Daily commute", commute: true)
    create(:workout, user:, sport: cycling, title: "Weekend ride")

    get workouts_path, params: { commute: "commute" }
    expect(response.body).to include("Daily commute")
    expect(response.body).not_to include("Weekend ride")

    get workouts_path, params: { commute: "non_commute" }
    expect(response.body).to include("Weekend ride")
    expect(response.body).not_to include("Daily commute")
  end

  it "searches titles and descriptions" do
    create(:workout, user:, sport: running, title: "Morning intervals", description: "track session")
    create(:workout, user:, sport: running, title: "Evening commute", description: "easy spin")

    get workouts_path, params: { q: "intervals" }

    expect(response.body).to include("Morning intervals")
    expect(response.body).not_to include("Evening commute")
  end

  it "offers every practiced sport as a select-group option outside the retracted panel, most used first" do
    create_list(:workout, 2, user:, sport: running)
    create(:workout, user:, sport: cycling)

    get workouts_path

    page = Nokogiri::HTML(response.body)
    options = page.css(".allure-filter-bar .allure-sport-filter .form-selectgroup-item")
    expect(options.size).to eq(2)
    expect(options.first.text).to include(running.translated_name, "2")
    expect(options.last.text).to include(cycling.translated_name, "1")
    expect(options.first.at_css("input[name='sports[]'][value='#{running.id}']")).to be_present
    # Every size shows the icon, the name and the count; phones scroll the row.
    expect(options.first.at_css(".allure-sport-filter__icon svg")).to be_present
    expect(options.first.at_css(".d-none")).to be_nil
    expect(options.first.at_css(".allure-sport-filter__count").text).to eq("2")
    expect(page.at_css("#workout-filters .allure-sport-filter")).to be_nil
    expect(page.at_css("#workout-filters select[name='sports[]']")).to be_nil
  end

  it "checks the active sport option and keeps the ranking unfiltered" do
    create_list(:workout, 2, user:, sport: running)
    create(:workout, user:, sport: cycling)

    get workouts_path, params: { sports: [ cycling.id.to_s ] }

    options = Nokogiri::HTML(response.body).css(".allure-filter-bar .allure-sport-filter .form-selectgroup-item")
    checked = options.filter_map { |option| option.at_css("input[checked]") }
    expect(checked.map { |input| input["value"] }).to eq([ cycling.id.to_s ])
    expect(options.map(&:text).join).to include(running.translated_name, cycling.translated_name)
  end

  it "hides the sport select-group when the account has no workouts" do
    get workouts_path

    expect(response.body).not_to include("allure-sport-filter")
  end

  it "sorts through one canonical key and still resolves the legacy pair" do
    create(:workout, user:, sport: running, title: "Short one", distance: 1_000)
    create(:workout, user:, sport: running, title: "Long one", distance: 20_000)

    get workouts_path, params: { sort: "distance_desc" }
    body = response.body
    expect(body.index("Long one")).to be < body.index("Short one")
    select = Nokogiri::HTML(body).at_css("select[name=sort]")
    expect(select.at_css("option[selected]")["value"]).to eq("distance_desc")
    expect(select.css("option").size).to eq(WorkoutsController::FILTER_SORT_KEYS.size)

    get workouts_path, params: { sort: "distance", direction: "asc" }
    body = response.body
    expect(body.index("Short one")).to be < body.index("Long one")
  end

  it "sorts without resetting on filter changes and keeps params in pagination" do
    create(:workout, user:, sport: running, title: "Short one", distance: 1_000)
    create(:workout, user:, sport: running, title: "Long one", distance: 20_000)

    get workouts_path, params: { sort: "distance_desc", sports: [ running.id.to_s ] }
    expect(response.body).to include("sort=distance_desc")
  end

  it "hands the filtered next page to the infinite-scroll loader" do
    create_list(:workout, 21, user:, sport: running, distance: 5_000)

    get workouts_path, params: { sort: "distance_desc", sports: [ running.id.to_s ] }

    url = Nokogiri::HTML(response.body).at_css("[data-infinite-scroll-url-value]")["data-infinite-scroll-url-value"]
    expect(url).to include("page=2", "sort=distance_desc", "sports%5B%5D=#{running.id}")
  end

  it "filters on the viewer's calendar windows, not rolling offsets" do
    travel_to(Time.zone.local(2026, 9, 16, 12, 0, 0)) do
      create(:workout, user:, sport: running, title: "This week", started_at: Time.zone.local(2026, 9, 16, 8))
      create(:workout, user:, sport: running, title: "Last week", started_at: Time.zone.local(2026, 9, 9, 8))
      create(:workout, user:, sport: running, title: "Last month", started_at: Time.zone.local(2026, 8, 1, 8))
      create(:workout, user:, sport: running, title: "Two years ago", started_at: Time.zone.local(2024, 3, 1, 8))

      get workouts_path, params: { period: "week" }
      expect(response.body).to include("This week")
      expect(response.body).not_to include("Last week", "Last month", "Two years ago")

      get workouts_path, params: { period: "days30" }
      expect(response.body).to include("This week", "Last week")
      expect(response.body).not_to include("Last month", "Two years ago")

      get workouts_path, params: { period: "year" }
      expect(response.body).to include("This week", "Last month")
      expect(response.body).not_to include("Two years ago")

      get workouts_path, params: { period: "all" }
      expect(response.body).to include("This week", "Two years ago")
    end
  end

  it "keeps a preset period in the toolbar, out of the drawer badge and the chips" do
    create(:workout, user:, sport: running, title: "Steady one")

    get workouts_path, params: { period: "days30" }

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".allure-filter-bar__controls select[name=period] option[selected]")["value"]).to eq("days30")
    expect(page.at_css(".allure-filter-bar button.filter-toggle .badge")).to be_nil
    expect(page.css(".allure-filter-bar .badge").map(&:text).join)
      .not_to include(I18n.t("workouts.index.filters.periods.days30"))
    expect(page.css(".allure-filter-bar a").map { |link| link.text.strip }).to include(I18n.t("workouts.index.filters.clear"))
  end

  it "badges and chips a custom range, whose dates live in the drawer" do
    create(:workout, user:, sport: running, title: "Steady one")

    get workouts_path, params: { period: "custom", from: "2026-01-01", to: "2026-02-01" }

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".allure-filter-bar button.filter-toggle .badge").text.strip).to eq("1")
    expect(page.css(".allure-filter-bar .badge").map(&:text).join).to include("2026-01-01")
    expect(page.at_css("#workout-filters [data-filter-bar-target='range']").key?("hidden")).to be(false)

    get workouts_path
    expect(Nokogiri::HTML(response.body).at_css("#workout-filters [data-filter-bar-target='range']").key?("hidden")).to be(true)
  end

  it "renders chips, a live count, and the filtered empty state" do
    create(:workout, user:, sport: running, title: "Only run")

    get workouts_path, params: { q: "nothing-matches-this", publication: "published" }

    expect(response.body).to include(I18n.t("workouts.index.filtered_empty.title"))
    expect(response.body).to include(I18n.t("workouts.index.filters.clear"))
    expect(response.body).to include("aria-live=\"polite\"")
    expect(response.body).not_to include(I18n.t("workouts.index.empty.title"))
  end

  it "sections the date-sorted card list by month and hands the separator to the endless scroll" do
    create(:workout, user:, sport: running, title: "September one", started_at: Time.zone.local(2026, 9, 16, 8))
    create(:workout, user:, sport: running, title: "September two", started_at: Time.zone.local(2026, 9, 2, 8))
    create(:workout, user:, sport: running, title: "August one", started_at: Time.zone.local(2026, 8, 30, 8))

    get workouts_path

    page = Nokogiri::HTML(response.body)
    separators = page.css("[data-workout-month]")
    expect(separators.map { |node| node["data-workout-month"] }).to eq(%w[2026-09-01 2026-08-01])
    expect(separators.first.at_css("h2.allure-list-separator").text).to eq("septembre 2026")
    expect(separators.first["class"]).to include("col-12")
    expect(page.at_css("[data-infinite-scroll-dedupe-attribute-value]")["data-infinite-scroll-dedupe-attribute-value"])
      .to eq("data-workout-month")

    # The sections are ordered and the cards stay inside them.
    items = page.at_css("[data-infinite-scroll-target='items']")
    expect(items.text.index("septembre 2026")).to be < items.text.index("août 2026")
    expect(items.text.index("September one")).to be < items.text.index("August one")
  end

  it "drops the month sections when the list is not date-sorted" do
    create(:workout, user:, sport: running, title: "Short one", distance: 1_000, started_at: Time.zone.local(2026, 9, 16, 8))
    create(:workout, user:, sport: running, title: "Long one", distance: 20_000, started_at: Time.zone.local(2026, 8, 2, 8))

    get workouts_path, params: { sort: "distance_desc" }

    page = Nokogiri::HTML(response.body)
    expect(page.css("[data-workout-month]")).to be_empty
    expect(page.at_css("[data-infinite-scroll-dedupe-attribute-value]")["data-infinite-scroll-dedupe-attribute-value"]).to eq("")
  end

  it "toggles the table layout through a segmented view switch" do
    create(:workout, user:, sport: running, title: "Table row")

    get workouts_path, params: { view: "table" }

    page = Nokogiri::HTML(response.body)
    expect(response.body).to include("<th scope=", "Table row")
    switch = page.at_css(".page-header nav.nav-segmented")
    active = switch.css("a[aria-current='true']")
    expect(active.size).to eq(1)
    expect(active.first["aria-label"]).to eq(I18n.t("workouts.index.view.table"))

    get workouts_path
    switch = Nokogiri::HTML(response.body).at_css(".page-header nav.nav-segmented")
    expect(switch.at_css("a[aria-current='true']")["aria-label"]).to eq(I18n.t("workouts.index.view.card"))
  end

  it "keeps the view mode in the filter form, so changing a filter or the sort never resets it" do
    create(:workout, user:, sport: running, title: "Table row")

    get workouts_path, params: { view: "table", sort: "distance_desc" }

    form = Nokogiri::HTML(response.body).at_css(".allure-filter-bar form")
    expect(form.at_css("input[name=view]")["value"]).to eq("table")

    # What the browser submits when the sort select changes.
    get workouts_path, params: { view: "table", period: "all", publication: "all",
                                 commute: "all", place: "", q: "", sort: "distance_desc" }

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".card table")).to be_present
    expect(page.at_css(".allure-workout-list")).to be_present
    expect(page.at_css(".row-cards")).to be_nil

    get workouts_path

    form = Nokogiri::HTML(response.body).at_css(".allure-filter-bar form")
    expect(form.at_css("input[name=view]")).to be_nil
  end

  it "keeps the view mode in every list action: chips, clear, headers, pager and the filtered empty state" do
    create_list(:workout, 21, user:, sport: running, title: "Row", distance: 5_000)

    get workouts_path, params: { view: "table", q: "Row" }

    page = Nokogiri::HTML(response.body)
    chip = page.css(".allure-filter-bar .badge a").first
    expect(chip["href"]).to include("view=table")
    clear = page.css(".allure-filter-bar a").find { |link| link.text.strip == I18n.t("workouts.index.filters.clear") }
    expect(clear["href"]).to include("view=table")
    expect(page.css("th a").map { |link| link["href"] }).to all(include("view=table"))
    expect(page.at_css("[data-infinite-scroll-url-value]")["data-infinite-scroll-url-value"]).to include("view=table")

    get workouts_path, params: { view: "table", q: "nothing-matches-this" }

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".empty-action a")["href"]).to include("view=table")
  end

  it "renders the table's phone mode as stacked rows, never the card grid" do
    workout = create(:workout, user:, sport: running, title: "Listed row", distance: 10_000,
                               duration: 3_600, moving_time: 3_600, pause_time: 0, ascent: 120)

    get workouts_path, params: { view: "table" }

    page = Nokogiri::HTML(response.body)
    list = page.at_css(".allure-workout-list")
    expect(list).to be_present
    row = list.at_css("li.list-group-item")
    expect(row.at_css("a.stretched-link").text).to eq(workout.title)
    expect(row.text).to include("10,0 km")
    expect(row.text).to include("1:00:00")
    # An unpublished row carries no badge, like the cards.
    expect(row.at_css("[data-audience-state]")).to be_nil
    expect(row.at_css("img")).to be_nil
    expect(page.at_css(".d-md-none .row-cards")).to be_nil
  end

  it "sorts from the table headers with aria-sort and toggling direction" do
    create(:workout, user:, sport: running, title: "Short one", distance: 1_000, ascent: 10)
    create(:workout, user:, sport: running, title: "Long one", distance: 20_000, ascent: 500)

    get workouts_path, params: { view: "table", sort: "distance_asc" }

    page = Nokogiri::HTML(response.body)
    header = page.css("th").find { |cell| cell.text.include?(I18n.t("workouts.index.table.distance")) }
    expect(header["aria-sort"]).to eq("ascending")
    expect(header.at_css("a")["href"]).to include("sort=distance_desc")

    body = response.body
    expect(body.index("Short one")).to be < body.index("Long one")

    get workouts_path, params: { view: "table", sort: "distance_desc" }
    page = Nokogiri::HTML(response.body)
    header = page.css("th").find { |cell| cell.text.include?(I18n.t("workouts.index.table.distance")) }
    expect(header["aria-sort"]).to eq("descending")
    expect(header.at_css("a")["href"]).to include("sort=distance_asc")
    expect(response.body.index("Long one")).to be < response.body.index("Short one")

    get workouts_path, params: { view: "table" }
    header = Nokogiri::HTML(response.body).css("th").find { |cell| cell.text.include?(I18n.t("workouts.index.table.distance")) }
    expect(header["aria-sort"]).to eq("none")
  end

  it "shows D+ and the sharing state in the table, and drops D+ from the phone rows" do
    published = create(:workout, user:, sport: running, title: "Published ride", ascent: 320)
    create(:workout_publication, workout: published)
    create(:workout, user:, sport: running, title: "Draft ride", ascent: 40)

    get workouts_path, params: { view: "table" }

    page = Nokogiri::HTML(response.body)
    expect(page.css("th").map(&:text).join).to include(I18n.t("workouts.index.table.state"), I18n.t("workouts.index.table.ascent"))
    published_row = page.css("tbody tr").find { |row| row.text.include?("Published ride") }
    expect(published_row.text).to include("320 m")
    expect(published_row.at_css("[data-audience-state='public']")).to be_present
    draft_row = page.css("tbody tr").find { |row| row.text.include?("Draft ride") }
    expect(draft_row.at_css("[data-audience-state='unpublished']")).to be_present

    list = page.at_css(".allure-workout-list")
    expect(list.text).not_to include("320 m")
  end

  it "rejects invalid filter values without raising" do
    create(:workout, user:, sport: running, title: "Steady one")

    get workouts_path, params: { sort: "hacker", direction: "sideways", period: "never", publication: "everyone", commute: "maybe" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Steady one")
    expect(response.body).to include("date_desc")
  end
end
