# frozen_string_literal: true

require "rails_helper"

# docs/dev/SHARED-ACTIVITIES.md: a credit row is the participant's own activity,
# read-only except for its deletion, and nothing in it is drawn from a track.
RSpec.describe "Workout credit rows" do
  let(:owner) { create(:user, username: "marie") }
  let(:participant) { create(:user, username: "paul") }
  let!(:owner_actor) { create(:local_actor, user: owner) }
  let(:participant_actor) { create(:local_actor, user: participant) }
  let(:source) { create(:workout, user: owner, title: "Sortie du soir", distance: 42_000) }
  let!(:participation) { create(:workout_participation, workout: source, participant_actor:) }
  let!(:credit) { Participations::CreditRows.attach(participation) }

  describe "the participant" do
    before { sign_in_as(participant) }

    it "reads the credited metrics, the badge to the source and the removal, nothing else" do
      get workout_path(credit)

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Sortie du soir")
      expect(body).to include(ERB::Util.html_escape(I18n.t("workouts.credit.metrics_hint")))
      expect(body).to include("Avec #{owner.display_name}")
      expect(body).to include(workout_path(source))
      expect(body).to include(ERB::Util.html_escape(I18n.t("workouts.credit.remove")))
      expect(body).not_to include(edit_workout_path(credit))
      expect(body).not_to include(ERB::Util.html_escape(I18n.t("workouts.show.map.title")))
      expect(body).not_to include(ERB::Util.html_escape(I18n.t("workouts.publication.publish")))
      # The card's section, not its title: the word also appears in release notes.
      expect(body).not_to include('id="section-participants"')
    end

    it "says the route is not visible while the source is unpublished" do
      get workout_path(credit)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.credit.route_hidden")))
    end

    it "shows the source's published map, through the publication this account may read" do
      create(:track_segment, workout: source)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      publish_workout!(user: owner, workout: source, profile:)

      get workout_path(credit)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.show.map.title")))
      expect(response.body).to include(workout_track_path(source))
      expect(response.body).not_to include(workout_track_path(credit))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("workouts.credit.route_hidden")))
    end

    it "shows the credited analysis rows: segments and best efforts only" do
      segment = create(:segment, user: participant, sport: credit.sport, name: "Côte du test")
      create(:segment_effort, workout: credit, segment:, user: participant,
                              average_heart_rate: nil, max_heart_rate: nil, average_cadence: nil,
                              average_power: nil, max_power: nil)

      get workout_path(credit)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.show.laps.title")))
      expect(response.body).to include("Côte du test")
      expect(response.body).to include('id="workout-laps-tab-segments"')
      expect(response.body).not_to include('id="workout-laps-tab-climbs"')
    end

    it "offers to link the participant's own recording, which replaces the credit" do
      recording = create(:workout, user: participant, title: "Ma montre", started_at: source.started_at + 5.minutes)

      get workout_path(credit)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.participations.convert")))
      expect(response.body).to include("Ma montre")

      patch convert_workout_participation_path(source, participation), params: { participant_workout_id: recording.to_param }

      expect(response).to redirect_to(workout_path(recording))
      expect(Workout.exists?(credit.id)).to be(false)
      expect(participation.reload.kind).to eq("link")

      # The linked recording names its source, on its page and on its card.
      get workout_path(recording)
      header = response.parsed_body.at_css(".page-pretitle a[data-badge='together']")
      expect(header["class"]).to include("allure-badge-responsive")
      expect(header["href"]).to eq(workout_path(source))

      get workouts_path
      card = response.parsed_body.css(".card").find { |node| node.text.include?("Ma montre") }
      expect(card.at_css(".workout-card__badges a[data-badge='together'].allure-badge-icon")["href"])
        .to eq(workout_path(source))
    end

    it "says the source is gone once it is deleted" do
      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!

      get workout_path(credit)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("workouts.credit.badge_detached", name: owner.display_name))
      )
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.credit.route_gone")))
      expect(response.body).not_to include("Sortie du soir")
      # The badge stays, grey and no longer a link.
      badge = response.parsed_body.at_css(".page-pretitle [data-badge='together']")
      expect(badge.name).to eq("span")
      expect(badge["class"]).to include("bg-secondary-lt")
    end

    it "lists it with its badge and no route image placeholder or bulk checkbox" do
      get workouts_path
      expect(response.body).to include("Avec #{owner.display_name}")
      # The card's « Avec @X » is an icon-only state badge opening the source
      # (DESIGN.md §10.4, §10.18).
      together = response.parsed_body.at_css(".workout-card__badges a[data-badge='together']")
      expect(together["class"]).to include("allure-badge-icon", "bg-primary-lt")
      expect(together["href"]).to eq(workout_path(source))
      expect(together["data-bs-title"]).to eq("Avec #{owner.display_name}")
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("workouts.route_image.pending")))

      get workouts_path(view: "table")
      expect(response.body).not_to include(%(value="#{credit.to_param}"))
    end

    it "shows the source publication's route image on its card, never the source's own" do
      create(:track_segment, workout: source)
      profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      publication = publish_workout!(user: owner, workout: source, profile:)
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("\x89PNG\r\n\x1A\n".b),
                                                    filename: "sanitized.png", content_type: "image/png")
      publication.attach_sanitized_route_image!(blob)

      get workouts_path

      expect(response.body).to include(publication_route_image_path(publication))
      expect(response.body).not_to include(workout_route_image_path(source))
      expect(response.body).not_to include(workout_route_image_path(credit))
    end

    it "refuses every owner action but the deletion" do
      [
        [ :get, edit_workout_path(credit) ],
        [ :patch, workout_path(credit) ],
        [ :post, publish_workout_path(credit) ],
        [ :get, publication_preview_workout_path(credit) ],
        [ :post, workout_regenerate_route_image_path(credit) ],
        [ :patch, workout_elevation_source_path(credit) ],
        [ :get, workout_toponymy_path(credit) ],
        [ :get, new_workout_segment_path(credit) ],
        [ :get, new_workout_route_path(credit) ]
      ].each do |verb, path|
        public_send(verb, path)
        expect(response).to have_http_status(:not_found), "#{verb.upcase} #{path}"
      end
    end

    it "cannot invite anyone from it" do
      expect {
        post workout_participations_path(credit), params: { participation: { handle: "marie" } }
      }.not_to change(WorkoutParticipation, :count)
    end

    it "removes it, which withdraws the participation" do
      delete workout_path(credit)

      expect(Workout.exists?(credit.id)).to be(false)
      expect(participation.reload).to be_withdrawn
    end
  end

  it "is invisible to anyone else" do
    sign_in_as(owner)

    get workout_path(credit)

    expect(response).to have_http_status(:not_found)
  end

  describe "REST API" do
    let(:headers) { api_headers_for(participant, scopes: %w[read write publish], "Content-Type" => "application/json") }

    it "says it is credited, by whom, without a track or file link" do
      get "/api/rest/v1/workouts/#{credit.to_param}", headers: headers

      expect(response).to have_http_status(:ok)
      expect_api_contract
      body = response.parsed_body
      expect(body).to include("origin" => "credit", "import" => nil, "import_format" => nil)
      expect(body["credit"]).to include("source_deleted" => false)
      expect(body["credit"]["recorded_by"]).to include("display_name" => owner.display_name, "deleted" => false)
      expect(body["links"].keys).to contain_exactly("self", "web")
      expect(body.to_json).not_to include(source.to_param)

      get "/api/rest/v1/workouts", headers: headers
      expect_api_contract
      expect(response.parsed_body["data"].pick("origin")).to eq("credit")
    end

    it "says when the source is gone, and keeps a recording's shape unchanged" do
      Workouts::WorkoutDeletion.new(user: owner, workout: source).call!
      recording = create(:workout, user: participant)

      get "/api/rest/v1/workouts/#{credit.to_param}", headers: headers
      expect(response.parsed_body["credit"]["source_deleted"]).to be(true)

      get "/api/rest/v1/workouts/#{recording.to_param}", headers: headers
      expect_api_contract
      expect(response.parsed_body).to include("origin" => "import", "credit" => nil)
      expect(response.parsed_body["links"].keys).to include("track", "original")
    end

    it "lists and reads it, and refuses to change or publish it" do
      get "/api/rest/v1/workouts/#{credit.to_param}", headers: headers
      expect(response).to have_http_status(:ok)

      patch "/api/rest/v1/workouts/#{credit.to_param}", params: { title: "Mine" }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect_api_contract(request: false)
      expect(response.parsed_body["code"]).to eq("credited_workout")

      profile = create(:publishing_profile, :without_endpoint_masks, user: participant)
      post "/api/rest/v1/workouts/#{credit.to_param}/publications",
           params: { publishing_profile_id: Allure::ShortId.encode(profile.uuid), acknowledge: true }.to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("credited_workout")
      expect(credit.reload.title).to eq("Sortie du soir")
    end
  end
end
