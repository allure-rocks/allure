# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Segment opt-outs" do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:sport) { create(:sport) }
  let(:segment) { create(:segment, user: owner, sport:, visibility: "public") }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  it "excludes the athlete idempotently and lets them rejoin" do
    sign_in(viewer)

    expect { post segment_opt_out_path(segment) }.to change(SegmentOptOut, :count).by(1)
    expect(response).to redirect_to(segment_path(segment))

    expect { post segment_opt_out_path(segment) }.not_to change(SegmentOptOut, :count)

    expect { delete segment_opt_out_path(segment) }.to change(SegmentOptOut, :count).by(-1)
    expect(response).to redirect_to(segment_path(segment))
  end

  it "does not require a matched effort" do
    sign_in(viewer)

    expect(segment.segment_efforts.exists?(user: viewer)).to be(false)
    post segment_opt_out_path(segment)

    expect(segment.opted_out?(viewer)).to be(true)
  end

  it "allows the owner to exclude their own effort" do
    sign_in(owner)

    post segment_opt_out_path(segment)

    expect(segment.opted_out?(owner)).to be(true)
  end

  it "404s a private segment and a followers-only segment the viewer cannot read" do
    private_segment = create(:segment, user: owner, sport:)
    followers_segment = create(:segment, user: owner, sport:, visibility: "followers_only")
    sign_in(viewer)

    post segment_opt_out_path(private_segment)
    expect(response).to have_http_status(:not_found)

    post segment_opt_out_path(followers_segment)
    expect(response).to have_http_status(:not_found)
  end

  it "removes the athlete's row from the board and restores it on rejoin" do
    workout = create(:workout, user: viewer, sport:)
    create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(viewer), status: "active")
    create(:segment_effort, segment:, workout:, user: viewer, sport:)
    sign_in(viewer)

    expect(Segments::Listing.for_segment(segment, viewer:)).to be_exists

    post segment_opt_out_path(segment)
    expect(Segments::Listing.for_segment(segment, viewer:)).not_to be_exists

    delete segment_opt_out_path(segment)
    expect(Segments::Listing.for_segment(segment, viewer:)).to be_exists
  end

  it "renders the participation state and the toggle in the container and the menu" do
    workout = create(:workout, user: viewer, sport:)
    create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(viewer), status: "active")
    create(:segment_effort, segment:, workout:, user: viewer, sport:)
    sign_in(viewer)

    get segment_path(segment)
    page = response.parsed_body
    expect(page.text).to include(
      I18n.t("segments.leaderboard.container_title"),
      I18n.t("segments.listing.reach.public"),
      I18n.t("segments.listing.exclude")
    )
    expect(page.css("form[action='#{segment_opt_out_path(segment)}']").size).to eq(2)

    post segment_opt_out_path(segment)
    get segment_path(segment)
    page = response.parsed_body
    expect(page.text).to include(I18n.t("segments.listing.reach.opted_out"), I18n.t("segments.listing.rejoin"))
    expect(page.css("form[action='#{segment_opt_out_path(segment)}']").size).to eq(2)
  end

  it "does not render the Classements container on a private segment" do
    private_segment = create(:segment, user: owner, sport:)
    sign_in(owner)

    get segment_path(private_segment)

    expect(response.body).not_to include(I18n.t("segments.leaderboard.container_title"))
  end
end
