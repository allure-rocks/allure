# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Segment publishing" do
  let(:user) { create(:user) }
  let(:segment) { create(:segment, user:, visibility: "public") }

  def sign_in(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  describe "owner controls" do
    before { sign_in }

    it "publishes, republishes after an edit, and withdraws" do
      expect { post publish_segment_path(segment) }.to change(SegmentPublication, :count).by(1)
      expect(response).to redirect_to(segment_path(segment))
      publication = SegmentPublication.order(:id).last
      expect(publication).to be_active

      segment.update!(name: "Nouveau nom")

      expect { post republish_segment_path(segment) }.to change(SegmentPublication, :count).by(1)
      expect(publication.reload).to be_deleted
      expect(segment.reload.active_publication.representation["name"]).to eq("Nouveau nom")

      expect { delete publication_segment_path(segment) }
        .to change { segment.reload.active_publication }.to(nil)
      expect(response).to redirect_to(segment_path(segment))
    end

    it "carries the publish action and the preview sentence in the header menu" do
      get segment_path(segment)

      page = response.parsed_body
      menu = page.at_css("button[aria-label='#{I18n.t('segments.show.actions.menu')}'] + .dropdown-menu")
      expect(menu).to be_present
      expect(menu.text).to include(I18n.t("segments.publication.preview"))
      expect(menu.at_css("form[action='#{publish_segment_path(segment)}']")).to be_present
      expect(page.text).not_to include(I18n.t("segments.publication.title"))
    end

    it "shows the publication state as a header badge" do
      get segment_path(segment)
      expect(response.body).to include(I18n.t("segments.publication.unpublished"))
      expect(response.parsed_body.at_css(%(.page-header [data-audience-state="unpublished"].allure-badge-responsive))).to be_present

      Segments::Publisher.new(user:, segment:).call!
      get segment_path(segment)
      expect(response.body).to include(
        I18n.t("segments.publication.published_as", audience: I18n.t("segments.publication.audience.public"))
      )
      # The same badge as a workout's: green, the publication mark, the course's
      # own wording (§10.4).
      published = response.parsed_body.at_css(%(.page-header [data-audience-state="public"].allure-badge-responsive))
      expect(published["class"]).to include("bg-success-lt")
      expect(published.at_css(".ti-broadcast")).to be_present
      expect(published.at_css(".allure-badge-responsive__label").text).to eq(
        I18n.t("segments.publication.published_as", audience: I18n.t("segments.publication.audience.public"))
      )

      segment.update!(name: "Nouveau nom")
      get segment_path(segment)
      expect(response.body).to include(I18n.t("segments.publication.stale"))
    end

    it "offers republish and withdraw from the menu once published and edited" do
      Segments::Publisher.new(user:, segment:).call!
      segment.update!(name: "Nouveau nom")

      get segment_path(segment)

      menu = response.parsed_body.at_css("button[aria-label='#{I18n.t('segments.show.actions.menu')}'] + .dropdown-menu")
      expect(menu.at_css("form[action='#{republish_segment_path(segment)}']")).to be_present
      expect(menu.at_css("form[action='#{publication_segment_path(segment)}']")).to be_present
      expect(menu.at_css("form[action='#{publish_segment_path(segment)}']")).to be_nil
    end

    it "offers no publication action on a private course" do
      private_segment = create(:segment, user:)

      get segment_path(private_segment)

      page = response.parsed_body
      expect(page.at_css("form[action='#{publish_segment_path(private_segment)}']")).to be_nil
      menu = page.at_css("button[aria-label='#{I18n.t('segments.show.actions.menu')}'] + .dropdown-menu")
      expect(menu.text).to include(I18n.t("segments.publication.private_hint"))
    end

    it "blocks making the segment more restrictive while published" do
      post publish_segment_path(segment)

      patch segment_path(segment), params: { segment: { visibility: "followers_only" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(segment.reload.visibility).to eq("public")
    end

    it "withdraws before deleting a published segment" do
      post publish_segment_path(segment)
      publication = segment.reload.active_publication

      expect { delete segment_path(segment) }.to change(Segment, :count).by(-1)

      expect(publication.reload).to be_deleted
      expect(
        FederationOutboxEvent.where(activity_type: "Delete", object_uri: publication.object_uri)
      ).to exist
    end

    it "404s publishing another user's segment" do
      other_segment = create(:segment, visibility: "public")

      post publish_segment_path(other_segment)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "protocol object" do
    let(:publication) { Segments::Publisher.new(user:, segment:).call! }

    it "serves a public course without a session" do
      publication
      get segment_publication_path(publication)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/activity+json")
      expect(JSON.parse(response.body)).to include(
        "id" => publication.object_uri,
        "type" => "Note",
        "attributedTo" => publication.actor.uri
      )
    end

    it "serves the GPX media and 404s an absent route image" do
      publication
      get segment_publication_gpx_path(publication)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/gpx+xml")

      get segment_publication_route_image_path(publication)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a withdrawn publication" do
      publication
      Segments::PublicationWithdrawal.new(user:, segment:).call!

      get segment_publication_path(publication)

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a followers-only course without a signed request" do
      followers_segment = create(:segment, user:, visibility: "followers_only")
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      publication = Segments::Publisher.new(user:, segment: followers_segment).call!

      get segment_publication_path(publication)

      expect(response).to have_http_status(:not_found)
    end
  end
end
