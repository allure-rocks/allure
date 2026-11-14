# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout photos" do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let(:photo) { Workouts::PhotoUpload.new(user:, workout:).call(StringIO.new(photo_bytes)) }
  before { sign_in_as(user) }

  it "uploads a photo and returns its public identifier" do
    post workout_photos_path(workout), params: { file: photo_upload }
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["id"]).to eq(workout.photos.sole.to_param)
  end

  it "serves original bytes as an attachment, never a storage redirect" do
    get workout_photo_path(workout, photo, variant: :original)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to start_with("attachment")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body.b).to eq(photo.original.download)
  end

  it "serves stripped derivatives only after processing" do
    get workout_photo_path(workout, photo, variant: :thumbnail)
    expect(response).to have_http_status(:not_found)
    Workouts::PhotoProcessJob.perform_now(photo)
    get workout_photo_path(workout, photo, variant: :thumbnail)
    expect(response.media_type).to eq("image/webp")
    expect(response).to have_http_status(:ok)
  end

  it "denies another member every action, including original and thumbnail" do
    photo
    sign_in_as(create(:user))
    %w[original display thumbnail].each do |variant|
      get workout_photo_path(workout, photo, variant:)
      expect(response).to have_http_status(:not_found)
    end
    post workout_photos_path(workout), params: { file: photo_upload }
    expect(response).to have_http_status(:not_found)
    patch workout_photo_path(workout, photo), params: { photo: { caption: "No" } }
    expect(response).to have_http_status(:not_found)
    delete workout_photo_path(workout, photo)
    expect(response).to have_http_status(:not_found)
  end

  it "edits a plain text caption and rejects overlong text" do
    patch workout_photo_path(workout, photo), params: { photo: { caption: "<script>plain text</script>" } }
    expect(photo.reload.caption).to eq("<script>plain text</script>")
    follow_redirect!
    expect(response.body).to include("&lt;script&gt;")
    patch workout_photo_path(workout, photo), params: { photo: { caption: "x" * 501 } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "reorders an exact set and rejects foreign or duplicate ids" do
    a = photo
    b = Workouts::PhotoUpload.new(user:, workout:).call(StringIO.new(photo_bytes))
    patch order_workout_photos_path(workout), params: { ids: [ b.to_param, a.to_param ] }
    expect(response).to have_http_status(:no_content)
    expect(workout.photos.reload.map(&:id)).to eq([ b.id, a.id ])
    patch order_workout_photos_path(workout), params: { ids: [ b.to_param, b.to_param ] }
    expect(response).to have_http_status(:not_found)
  end

  it "deletes photos with their workout and enqueues attachment purge" do
    photo
    expect { Workouts::WorkoutDeletion.new(user:, workout:).call! }.to change(WorkoutPhoto, :count).by(-1)
    expect(ActiveStorage::Attachment.where(record_type: "WorkoutPhoto")).to be_empty
    expect(enqueued_jobs.any? { |job| job[:job] == ActiveStorage::PurgeJob }).to be(true)
  end

  it "hides both the card and endpoints while disabled" do
    with_photo_env("PHOTOS_ENABLED" => "false") do
      get workout_photos_path(workout)
      expect(response).to have_http_status(:not_found)
      post workout_photos_path(workout), params: { file: photo_upload }
      expect(response).to have_http_status(:not_found)
    end
  end

  it "requires a browser session" do
    photo
    delete session_path
    get workout_photo_path(workout, photo, variant: :original)
    expect(response).to redirect_to(new_session_path)
  end

  it "renders an owner card for positionless and manual activities" do
    [ create(:workout, :unpositioned, user:), create(:workout, :manual, user:) ].each do |activity|
      get workout_path(activity)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="section-photos"')
      expect(response.body).not_to include("/rails/active_storage/")
    end
  end

  it "never exposes owner photos on a publication page or the owner's reader preview" do
    create(:track_segment, workout:)
    photo.update!(caption: "Private photo caption")
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    publish_workout!(user:, workout:, profile:)

    get workout_path(workout, as: "publication")
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('id="section-photos"', "Private photo caption", photo.to_param)

    sign_in_as(create(:user))
    get workout_path(workout)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('id="section-photos"', "Private photo caption", photo.to_param)
    get workout_photo_path(workout, photo, variant: :original)
    expect(response).to have_http_status(:not_found)
  end

  it "renders the owner's viewer with the position, the capture time and the map link" do
    create(:track_segment, workout:)
    Workouts::PhotoProcessJob.perform_now(photo)
    Workouts::PhotoPlacement.new(workout:).place(photo, longitude: 6.40835, latitude: 45.07185)
    photo.reload.update!(taken_at_local: Time.zone.local(2026, 10, 12, 14, 32))

    get workout_path(workout)

    page = response.parsed_body
    dialog = page.at_css(".allure-photo-dialog")
    expect(dialog.at_css("[data-photo-lightbox-target='counter']")).to be_present
    expect(dialog.at_css("[data-photo-lightbox-target='meta']")).to be_present
    expect(dialog.at_css("[data-photo-lightbox-target='map']")).to be_present
    preview = page.at_css(".allure-photo-preview")
    expect(preview["data-meta"]).to include("14:32")
    expect(preview["data-map"]).to eq("1")
  end

  it "offers a translated picker with the intake limits for client-side checks" do
    get workout_path(workout)

    page = response.parsed_body
    expect(page.at_css("[data-photo-upload-target='input']").key?("hidden")).to be(true)
    expect(page.at_css("button[data-action='photo-upload#choose']")).to be_present
    card = page.at_css("[data-controller='photo-upload']")
    expect(card["data-photo-upload-max-bytes-value"]).to eq(Allure::Photos::Config::MAX_BYTES.to_s)
    expect(card["data-photo-upload-max-value"]).to eq(Allure::Photos::Config::MAX_PER_WORKOUT.to_s)
    expect(card["data-photo-upload-remaining-value"]).to eq(Allure::Photos::Config::MAX_PER_WORKOUT.to_s)
  end

  it "names storage in the locale's units" do
    get workout_photos_path(workout)

    expect(response.body).to include("Go")
  end

  it "keeps the card to a glance: a count, the picker and the manager" do
    create(:track_segment, workout:)
    Workouts::PhotoProcessJob.perform_now(photo)

    get workout_path(workout)

    page = response.parsed_body
    expect(page.at_css("#section-photos .card-title").text).to include("1 photo")
    expect(page.at_css("#section-photos a[href='#{workout_photos_path(workout)}']")).to be_present
    expect(page.at_css("#section-photos button[data-action='photo-upload#choose']")).to be_present
    expect(page.at_css("#section-photos textarea")).to be_nil
    expect(page.at_css("#section-photos button[data-action='photo-placement#start']")).to be_nil
    expect(page.at_css("#section-photos form[action*='/order']")).to be_nil
  end

  it "shows the quota on the card only once it matters" do
    get workout_path(workout)
    expect(response.parsed_body.at_css("#section-photos progress")).to be_nil

    photo
    user.update!(photo_quota_bytes: photo.reload.bytes_total)
    get workout_path(workout)
    expect(response.parsed_body.at_css("#section-photos progress")).to be_present
  end

  it "links the lightbox to the photo's row in the manager" do
    create(:track_segment, workout:)
    Workouts::PhotoProcessJob.perform_now(photo)

    get workout_path(workout)

    preview = response.parsed_body.at_css("#section-photos .allure-photo-preview")
    expect(preview["data-edit"]).to eq(workout_photos_path(workout, anchor: "photo-#{photo.to_param}"))
    expect(response.parsed_body.at_css(".allure-photo-dialog [data-photo-lightbox-target='edit']")).to be_present
  end

  describe "the photo page" do
    before do
      create(:track_segment, workout:)
      Workouts::PhotoProcessJob.perform_now(photo)
    end

    it "shows the owner the manager, the map and the photo's facts" do
      photo.reload.update!(taken_at_local: Time.zone.local(2026, 10, 12, 14, 32))

      get workout_photos_path(workout)

      expect(response).to have_http_status(:ok)
      page = response.parsed_body
      expect(page.at_css("turbo-frame#photo-manager-#{workout.to_param}")).to be_present
      expect(page.at_css("#photo-#{photo.to_param}")).to be_present
      expect(page.at_css("#section-map")).to be_present
      expect(page.at_css("textarea[name='photo[caption]']")).to be_present
      expect(response.body).to include("14:32")
      expect(response.body).not_to include("/rails/active_storage/")
    end

    it "renders the manager alone for its own frame" do
      get workout_photos_path(workout), headers: { "Turbo-Frame" => "photo-manager-#{workout.to_param}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css("turbo-frame#photo-manager-#{workout.to_param}")).to be_present
      expect(response.parsed_body.at_css("h1")).to be_nil
    end

    it "renders the card's gallery for its own frame" do
      get gallery_workout_photos_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css("turbo-frame#photos-#{workout.to_param}")).to be_present
      expect(response.parsed_body.at_css("h1")).to be_nil
    end

    it "hides the map and the placement controls on a positionless activity" do
      activity = create(:workout, :unpositioned, user:)
      create(:track_segment, :unpositioned, workout: activity)
      uploaded = Workouts::PhotoUpload.new(user:, workout: activity).call(StringIO.new(photo_bytes))
      Workouts::PhotoProcessJob.perform_now(uploaded)

      get workout_photos_path(activity)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css("#section-map")).to be_nil
      expect(response.body).not_to include("Placer sur le parcours")
    end

    it "refuses the page to another account" do
      sign_in_as(create(:user))

      get workout_photos_path(workout)

      expect(response).to have_http_status(:not_found)
    end

    it "explains why a photo is not on the route" do
      photo.reload.update!(exif_location: Workouts::PhotoPlacement::FACTORY.point(6.5, 45.0))

      get workout_photos_path(workout)

      expect(response.body).to include("Hors du parcours")
      expect(response.body).to include("du tracé")
    end

    it "saves a caption as JSON and returns its label" do
      patch workout_photo_path(workout, photo), params: { photo: { caption: "Le col" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["label"]).to eq("Le col")
      expect(photo.reload.caption).to eq("Le col")
    end

    it "marks a manual order and resumes the automatic one" do
      second = Workouts::PhotoUpload.new(user:, workout:).call(StringIO.new(photo_bytes))
      Workouts::PhotoProcessJob.perform_now(second)

      patch order_workout_photos_path(workout), params: { ids: [ second.to_param, photo.to_param ] }
      expect(response).to have_http_status(:no_content)
      expect(workout.reload).to be_photos_ordered_by_owner

      patch sort_workout_photos_path(workout)
      expect(response).to have_http_status(:see_other)
      expect(workout.reload).not_to be_photos_ordered_by_owner
    end
  end

  describe "placement" do
    before do
      create(:track_segment, workout:)
      Workouts::PhotoProcessJob.perform_now(photo)
    end

    it "places a photo where the owner clicked, snapped onto the route" do
      patch placement_workout_photo_path(workout, photo), params: { mode: "manual", longitude: 6.40835, latitude: 45.07185 }, as: :json

      expect(response).to have_http_status(:ok)
      expect(photo.reload).to have_attributes(location_source: "manual")
      expect(photo.track_distance).to be_within(5).of(125)
    end

    it "refuses a click far from the route" do
      patch placement_workout_photo_path(workout, photo), params: { mode: "manual", longitude: 7.5, latitude: 45.0 }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
      expect(photo.reload.location_source).to eq("none")
    end

    it "clears and restores the automatic placement" do
      patch placement_workout_photo_path(workout, photo), params: { mode: "clear" }
      expect(response).to redirect_to(workout_photos_path(workout))
      expect(photo.reload.location_source).to eq("cleared")

      patch placement_workout_photo_path(workout, photo), params: { mode: "auto" }
      expect(photo.reload.location_source).to eq("none")
    end

    it "saves the camera correction within its bounds" do
      patch time_offset_workout_photos_path(workout), params: { offset_minutes: "-90" }
      expect(response).to redirect_to(workout_photos_path(workout))
      expect(workout.reload.photo_time_offset_seconds).to eq(-5_400)

      patch time_offset_workout_photos_path(workout), params: { offset_minutes: "900" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(workout.reload.photo_time_offset_seconds).to eq(-5_400)
    end

    it "draws placed photos on the owner's map and profile through the app's own endpoints" do
      Workouts::PhotoPlacement.new(workout:).place(photo, longitude: 6.40835, latitude: 45.07185)

      get workout_path(workout)

      page = response.parsed_body
      markers = JSON.parse(page.at_css("[data-controller='map']")["data-map-photos-value"])
      expect(markers.sole).to include("id" => photo.to_param, "thumbnail" => workout_photo_path(workout, photo, variant: :thumbnail))
      expect(page.at_css("[data-elevation-chart-photos-value]")).to be_present
      expect(response.body).not_to include("/rails/active_storage/")
    end

    it "refuses placement to another account" do
      sign_in_as(create(:user))
      patch placement_workout_photo_path(workout, photo), params: { mode: "clear" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
