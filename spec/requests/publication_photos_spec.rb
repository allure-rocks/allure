# frozen_string_literal: true

require "rails_helper"

# docs/dev/PHOTOS.md: readers see only what a publication froze, through the
# publication's own media endpoint.
RSpec.describe "Publication photos" do
  let(:owner) { create(:user) }
  let(:reader) { create(:user) }
  let(:workout) { create(:workout, user: owner) }
  let(:settings) { { "photos" => true, "photo_captions" => true, "photo_positions" => true } }
  let(:profile) do
    create(:publishing_profile, :without_endpoint_masks, user: owner,
                                                         settings: PublishingProfile::DEFAULT_SETTINGS.merge("mask_start" => false, "mask_finish" => false).merge(settings))
  end
  let!(:photo) do
    create(:track_segment, workout:)
    photo = Workouts::PhotoUpload.new(user: owner, workout:).call(StringIO.new(photo_bytes))
    Workouts::PhotoProcessJob.perform_now(photo)
    photo.reload.update!(caption: "Le col")
    Workouts::PhotoPlacement.new(workout:).place(photo, longitude: 6.4083, latitude: 45.0719)
    photo
  end
  let(:publication) { publish_workout!(user: owner, workout:, profile:) }
  let(:copy) { publication.photos.sole }

  it "shows a reader the frozen gallery, the map marker and the copy, never the owner's files" do
    publication
    sign_in_as(reader)

    get workout_path(workout)

    page = response.parsed_body
    expect(page.at_css("#section-photos img")["src"]).to eq(publication_photo_path(publication, copy.to_param, variant: "thumbnail"))
    expect(response.body).to include("Le col")
    expect(response.body).not_to include(photo.to_param, "/rails/active_storage/")
    marker = JSON.parse(page.at_css("[data-controller='map']")["data-map-photos-value"]).sole
    expect(marker).to include("id" => copy.to_param, "distance" => publication.representation["photos"].sole["distance"])
    expect(page.at_css("#section-photos input, #section-photos form")).to be_nil

    get publication_photo_path(publication, copy.to_param)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/webp")
    get workout_photo_path(workout, photo, variant: :thumbnail)
    expect(response).to have_http_status(:not_found)
  end

  it "shows the first photos on the reader's feed card" do
    publication
    sign_in_as(reader)

    get feed_path(public: 1)

    expect(response.body).to include(publication_photo_path(publication, copy.to_param, variant: "thumbnail"))
  end

  it "refuses the copy once the publication is withdrawn" do
    Workouts::PublicationWithdrawal.new(user: owner, workout:, publication:).call!
    sign_in_as(reader)

    get publication_photo_path(publication, copy.to_param)

    expect(response).to have_http_status(:not_found)
  end

  context "when the profile shares no positions" do
    let(:settings) { { "photos" => true } }

    it "draws no marker" do
      publication
      sign_in_as(reader)

      get workout_path(workout)

      expect(response.parsed_body.at_css("[data-map-photos-value]")).to be_nil
      expect(response.body).not_to include("Le col")
    end
  end

  it "gives the reader a viewer with the shared distance and a map link" do
    publication
    sign_in_as(reader)

    get workout_path(workout)

    page = response.parsed_body
    preview = page.at_css("#section-photos .allure-photo-preview")
    expect(preview["data-meta"]).to include("du départ")
    expect(preview["data-map"]).to eq("1")
    expect(page.at_css("#section-photos [data-photo-lightbox-target='counter']")).to be_present
    expect(page.at_css("#section-photos [data-photo-lightbox-target='map']")).to be_present
  end

  it "lists the ready photos only when the selected profile shares photos" do
    sign_in_as(owner)

    get new_publication_workout_path(workout)

    page = response.parsed_body
    choice = page.at_css("input[name='photo_ids[]'][value='#{photo.to_param}']")
    expect(choice["checked"]).to be_present
    expect(page.at_css("[data-publication-preview-target='photoChoice']").key?("hidden")).to be(true)
    expect(page.at_css("[data-publication-preview-target='photoOff']").key?("hidden")).to be(false)

    selected = PublishingProfile.find(page.at_css("select[name='publishing_profile_id'] option[selected]")["value"])
    selected.update!(settings: selected.settings.merge("photos" => true))

    get new_publication_workout_path(workout)

    page = response.parsed_body
    expect(page.at_css("[data-publication-preview-target='photoChoice']").key?("hidden")).to be(false)
    expect(page.at_css("[data-publication-preview-target='photoOff']").key?("hidden")).to be(true)
  end

  it "keeps an explicitly empty photo selection after a validation error" do
    sign_in_as(owner)

    post publish_workout_path(workout), params: { publishing_profile_id: profile.id, publish_delay: 10, photo_selection: "1" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css("input[name='photo_ids[]']")).to be_present
    expect(response.parsed_body.at_css("input[name='photo_ids[]'][checked]")).to be_nil
    expect(workout.reload.live_audiences).to be_empty
  end

  it "keeps a checked sensitive photo and the chosen delay when the acknowledgement is missing" do
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    photo.update!(exif_location: factory.point(6.4, 45.079))
    create(:privacy_zone, user: owner, center: photo.exif_location, radius_meters: 150)
    delay = PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
    profile
    sign_in_as(owner)

    get new_publication_workout_path(workout)
    expect(response.parsed_body.at_css("input[name='photo_ids[]'][checked]")).to be_nil

    post publish_workout_path(workout), params: {
      publishing_profile_id: profile.id, publish_delay: delay, photo_selection: "1", photo_ids: [ photo.to_param ]
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css("input[name='photo_ids[]'][checked]")["value"]).to eq(photo.to_param)
    expect(response.parsed_body.at_css("input[name='photos_acknowledged'][checked]")).to be_nil
    expect(response.parsed_body.at_css("select[name='publish_delay'] option[selected]")["value"]).to eq(delay.to_s)
    expect(workout.reload.live_audiences).to be_empty
  end

  it "publishes the owner's choice from the form" do
    sign_in_as(owner)

    post publish_workout_path(workout), params: { publishing_profile_id: profile.id, publish_delay: 0, photo_selection: "1" }

    expect(workout.reload.active_publications.sole.photos).to be_empty
  end

  it "saves the photo settings of a publishing profile" do
    sign_in_as(owner)

    patch publishing_profile_path(profile), params: { publishing_profile: { name: profile.name, settings: { photos: "1", photo_positions: "1", route: "1" } } }

    expect(profile.reload.settings).to include("photos" => true, "photo_positions" => true, "photo_captions" => false)
  end
end
