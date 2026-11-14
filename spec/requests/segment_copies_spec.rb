# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Segment copies" do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:sport) { create(:sport) }
  let(:source) { create(:segment, user: owner, sport:, visibility: "public") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  it "offers the two copy actions to a signed-in non-owner" do
    sign_in(viewer)

    get segment_path(source)

    menu = response.parsed_body.at_css("button[aria-label='#{I18n.t('segments.show.actions.menu')}'] + .dropdown-menu")
    expect(menu.text).to include(I18n.t("segments.copy.action"), I18n.t("segments.copy.reverse"))
    expect(menu.css("form[action='#{segment_copy_path(source)}']").size).to eq(2)
  end

  it "copies the course into the viewer's private segments and enqueues the backfill" do
    sign_in(viewer)
    source
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { post segment_copy_path(source), params: { direction: "forward" } }
      .to change(viewer.segments, :count).by(1)
      .and have_enqueued_job(Segments::BackfillSegmentJob).exactly(:once)

    copy = viewer.segments.order(:id).last
    expect(response).to redirect_to(segment_path(copy))
    expect(copy).to have_attributes(
      visibility: "private",
      source_workout: nil,
      name: source.name,
      distance: source.distance
    )
  end

  it "creates a reversed copy with swapped endpoints" do
    sign_in(viewer)

    post segment_copy_path(source), params: { direction: "reverse" }

    copy = viewer.segments.order(:id).last
    expect([ copy.start_point.x, copy.start_point.y ])
      .to eq([ source.end_point.x, source.end_point.y ])
    expect([ copy.end_point.x, copy.end_point.y ])
      .to eq([ source.start_point.x, source.start_point.y ])
    expect(copy.name).to eq(I18n.t("segments.copy.reversed_name", name: source.name))
  end

  it "offers the type-labelled reverse action to the owner, never the copies" do
    route = create(:segment, :route, user: owner, sport:)
    loop_segment = create(:segment, :loop, user: owner, sport:)
    sign_in(owner)

    get segment_path(source)
    menu = response.parsed_body.at_css("button[aria-label='#{I18n.t('segments.show.actions.menu')}'] + .dropdown-menu")
    expect(menu.text).to include(I18n.t("segments.copy.reverse_own.segment"))
    expect(menu.text).not_to include(I18n.t("segments.copy.action"), I18n.t("segments.copy.reverse"))

    get segment_path(route)
    menu = response.parsed_body.at_css("button[aria-label='#{I18n.t('segments.show.actions.menu')}'] + .dropdown-menu")
    expect(menu.text).to include(I18n.t("segments.copy.reverse_own.route"))

    get segment_path(loop_segment)
    menu = response.parsed_body.at_css("button[aria-label='#{I18n.t('segments.show.actions.menu')}'] + .dropdown-menu")
    expect(menu.css("form[action='#{segment_copy_path(loop_segment)}']")).to be_empty
  end

  it "creates the reversed copy of the owner's own segment" do
    sign_in(owner)
    source

    expect { post segment_copy_path(source), params: { direction: "reverse" } }
      .to change(owner.segments, :count).by(1)

    copy = owner.segments.order(:id).last
    expect(response).to redirect_to(segment_path(copy))
    expect(flash[:notice]).to eq(I18n.t("segments.copy.reverse_success"))
    expect(copy).to have_attributes(kind: "segment", visibility: "private")
    expect([ copy.start_point.x, copy.start_point.y ])
      .to eq([ source.end_point.x, source.end_point.y ])
  end

  it "creates the reversed copy of the owner's own route, preserving its kind" do
    route = create(:segment, :route, user: owner, sport:)
    sign_in(owner)

    expect { post segment_copy_path(route), params: { direction: "reverse" } }
      .to change(owner.segments, :count).by(1)

    copy = owner.segments.order(:id).last
    expect(copy).to have_attributes(kind: "route", visibility: "private")
    expect(response).to redirect_to(segment_path(copy))
  end

  it "denies the owner the forward copy of their own course" do
    sign_in(owner)

    post segment_copy_path(source), params: { direction: "forward" }

    expect(response).to have_http_status(:not_found)
  end

  it "requires authentication" do
    post segment_copy_path(source), params: { direction: "forward" }

    expect(response).to redirect_to(new_session_path)
  end

  it "404s an unreadable course and an unknown direction" do
    sign_in(viewer)
    private_segment = create(:segment, user: owner, sport:)

    post segment_copy_path(private_segment), params: { direction: "forward" }
    expect(response).to have_http_status(:not_found)

    post segment_copy_path(source), params: { direction: "sideways" }
    expect(response).to have_http_status(:not_found)
  end

  it "allows an accepted follower to copy a followers-only course" do
    follower = create(:user)
    followers_segment = create(:segment, user: owner, sport:, visibility: "followers_only")
    create(:local_actor, user: owner)
    create(:local_actor, user: follower)
    create(:following, :accepted, follower_actor: follower.actor, followed_actor: owner.actor)
    sign_in(follower)

    expect { post segment_copy_path(followers_segment), params: { direction: "forward" } }
      .to change(follower.segments, :count).by(1)
  end
end
