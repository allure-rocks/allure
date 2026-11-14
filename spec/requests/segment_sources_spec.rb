# frozen_string_literal: true

require "rails_helper"

# Course creation, step one (DESIGN.md §20.6): the owner chooses the source
# activity among their own positioned recordings, the most recent leading as
# a shortcut, then lands on the segment or route creation page.
RSpec.describe "Segment source picker" do
  let(:user) { create(:user) }

  def page_html = Nokogiri::HTML(response.body)

  def listed_links = page_html.css("ul.allure-source-list a.stretched-link").pluck("href")

  it "requires a signed-in account" do
    get new_segment_path

    expect(response).to redirect_to(new_session_path)
  end

  it "leads with the latest activity and lists the others, newest first, to the segment creation page" do
    older = create(:workout, user:, title: "Older ride", started_at: 3.days.ago)
    middle = create(:workout, user:, title: "Middle ride", started_at: 2.days.ago)
    latest = create(:workout, user:, title: "Latest ride", started_at: 1.day.ago)
    sign_in_as(user)

    get new_segment_path

    expect(response).to have_http_status(:ok)
    shortcut = page_html.at_css("section[aria-labelledby='segment-source-latest']")
    expect(shortcut.text).to include("Latest ride")
    expect(shortcut.at_css("a.btn-primary")["href"]).to eq(new_workout_segment_path(latest))
    expect(listed_links).to eq([ new_workout_segment_path(middle), new_workout_segment_path(older) ])
  end

  it "links to the route creation page for the route kind" do
    workout = create(:workout, user:)
    sign_in_as(user)

    get new_segment_path(kind: "route")

    expect(response.body).to include(I18n.t("segment_sources.new.pretitle.route"))
    expect(page_html.at_css("section a.btn-primary")["href"]).to eq(new_workout_route_path(workout))
  end

  it "offers only the viewer's own positioned recordings" do
    own = create(:workout, user:, started_at: 5.days.ago)
    create(:workout, :unpositioned, user:, started_at: 1.day.ago, title: "Indoor")
    create(:workout, :manual, user:, started_at: 2.days.ago, title: "Typed in")
    create(:workout, user: create(:user), started_at: 1.hour.ago, title: "Someone else")
    sign_in_as(user)

    get new_segment_path

    expect(page_html.at_css("section a.btn-primary")["href"]).to eq(new_workout_segment_path(own))
    expect(listed_links).to be_empty
    expect(response.body).not_to include("Indoor", "Typed in", "Someone else")
  end

  it "filters by a recorded place without the shortcut" do
    rochelune = create(:workout, user:, started_at: 3.days.ago)
    create(:workout_place_name, workout: rochelune, user:, name: "Rochelune", kind: "city", position: 0)
    create(:workout, user:, started_at: 1.day.ago)
    sign_in_as(user)

    get new_segment_path(place: "roc")

    expect(page_html.at_css("section[aria-labelledby='segment-source-latest']")).to be_nil
    expect(listed_links).to eq([ new_workout_segment_path(rochelune) ])
  end

  it "says when no activity goes through the place" do
    create(:workout, user:)
    sign_in_as(user)

    get new_segment_path(place: "Atlantis")

    expect(response.body).to include(I18n.t("segment_sources.new.filtered_empty", place: "Atlantis"))
  end

  it "points to the import page without any positioned recording" do
    create(:workout, :manual, user:)
    sign_in_as(user)

    get new_segment_path

    expect(response.body).to include(I18n.t("segment_sources.new.empty.title"))
    expect(page_html.at_css(".empty-action a")["href"]).to eq(new_workout_import_path)
  end

  describe "segment index entry" do
    before { sign_in_as(user) }

    it "opens the picker from the segments and routes tabs, never from loops" do
      get segments_path
      expect(page_html.css("a[href='#{new_segment_path}']")).to be_present

      get segments_path(kind: "route")
      expect(page_html.css("a[href='#{new_segment_path(kind: 'route')}']")).to be_present

      get segments_path(kind: "loop")
      expect(page_html.css("a[href^='#{new_segment_path}']")).to be_empty
      expect(page_html.css(".empty-action a")).to be_empty
    end
  end
end
