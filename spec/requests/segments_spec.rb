# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Segments" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }
  let(:workout) { create(:workout, user:, sport:, title: "Source workout", points_count: 3, distance: 200.0) }

  def sign_in_user(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  def add_source_points
    create(
      :track_segment,
      workout:,
      position: 0,
      distance: 200.0,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
        { "t" => 30, "d" => 100.0, "lat" => 45.0710, "lon" => 6.4084, "ele" => 105.0 },
        { "t" => 60, "d" => 200.0, "lat" => 45.0710, "lon" => 6.4094, "ele" => 110.0 }
      ]
    )
  end

  describe "owner access" do
    it "requires authentication" do
      get segments_path

      expect(response).to redirect_to(new_session_path)
    end

    it "lists every visible segment and hides the others' private ones" do
      own = create(:segment, user:, name: "Mon col")
      create(:segment, name: "Col public", visibility: "public")
      create(:segment, name: "Col privé")
      sign_in_user

      get segments_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mon col", "Col public")
      expect(response.body).not_to include("Col privé")
    end

    it "lists a followed owner's followers-only segment and hides a non-followed one" do
      followed_owner = create(:user)
      create(:segment, user: followed_owner, name: "Col des abonnés", visibility: "followers_only")
      create(:segment, user: create(:user), name: "Col caché", visibility: "followers_only")
      create(
        :following,
        :accepted,
        follower_actor: create(:actor, :local, user:),
        followed_actor: create(:actor, :local, user: followed_owner)
      )
      sign_in_user

      get segments_path

      expect(response.body).to include("Col des abonnés")
      expect(response.body).not_to include("Col caché")
    end

    it "renders the kind switcher as a segmented control, active on the current kind" do
      sign_in_user

      get segments_path(kind: "loop")

      expect(response.body).to include(
        "<h1 class=\"page-title\">#{I18n.t('segments.index.title')}</h1>",
        "nav nav-segmented",
        I18n.t("segments.index.kinds.label"),
        I18n.t("segments.index.kinds.loop")
      )
      expect(response.body).to match(/class="nav-link active"[^>]*aria-current="true"/)
      expect(response.body).not_to include("nav-tabs", "role=\"tab\"")
    end

    it "returns 404 for another user's segment" do
      segment = create(:segment, name: "Private course")
      sign_in_user

      get segment_path(segment)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "selection and creation" do
    it "renders the owner selection workspace" do
      add_source_points
      sign_in_user

      get new_workout_segment_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        workout_track_path(workout),
        workout_segment_selection_path(workout),
        "data-controller=\"segment-selection\"",
        "segment-creation-workspace",
        "allure-map--tall",
        'name="segment[source_start_index]"',
        'name="segment[source_end_index]"',
        "aria-live=\"polite\""
      )
    end

    it "exposes indexed selection data only to the workout owner" do
      add_source_points
      sign_in_user

      get workout_segment_selection_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.headers["Cache-Control"]).to eq("private, no-store")
      expect(response.parsed_body["points"]).to include(
        hash_including("index" => 0, "segment_index" => 0)
      )
    end

    it "does not expose selection data for another user's workout" do
      other_workout = create(:workout)
      sign_in_user

      get workout_segment_selection_path(other_workout)

      expect(response).to have_http_status(:not_found)
    end

    it "creates a segment from server-reconstructed source points" do
      add_source_points
      sign_in_user

      expect do
        post workout_segments_path(workout), params: {
          segment: {
            name: "Morning climb",
            description: "The useful part",
            source_start_index: 0,
            source_end_index: 2,
            match_tolerance_meters: 25
          }
        }
      end.to change(Segment, :count).by(1)

      segment = Segment.order(:id).last
      expect(response).to redirect_to(segment_path(segment))
      expect(segment.source_workout).to eq(workout)
      expect(segment.visibility).to eq("private")
    end

    it "creates a segment with the visibility chosen at creation" do
      add_source_points
      sign_in_user

      post workout_segments_path(workout), params: {
        segment: {
          name: "Shared part",
          source_start_index: 0,
          source_end_index: 2,
          match_tolerance_meters: 25,
          visibility: "followers_only"
        }
      }

      expect(Segment.order(:id).last.visibility).to eq("followers_only")
    end

    it "requires the corridor acknowledgment to create a shared segment through a privacy zone" do
      add_source_points
      create(:privacy_zone, user:)
      sign_in_user

      expect do
        post workout_segments_path(workout), params: {
          segment: {
            name: "Zoned part",
            source_start_index: 0,
            source_end_index: 2,
            match_tolerance_meters: 25,
            visibility: "public"
          }
        }
      end.not_to change(Segment, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("segments.form.corridor.confirm"))
    end

    it "creates the shared segment once the corridor is acknowledged" do
      add_source_points
      create(:privacy_zone, user:)
      sign_in_user

      post workout_segments_path(workout), params: {
        segment: {
          name: "Zoned part",
          source_start_index: 0,
          source_end_index: 2,
          match_tolerance_meters: 25,
          visibility: "public",
          acknowledge_privacy_zones: "1"
        }
      }

      segment = Segment.order(:id).last
      expect(response).to redirect_to(segment_path(segment))
      expect(segment.visibility).to eq("public")
      expect(segment.privacy_zone_acknowledged_at).to be_present
    end

    it "creates an all-sports segment when the sport is blank" do
      add_source_points
      sign_in_user

      post workout_segments_path(workout), params: {
        segment: {
          name: "Tous sports",
          source_start_index: 0,
          source_end_index: 2,
          match_tolerance_meters: 25,
          sport_id: ""
        }
      }

      expect(Segment.order(:id).last.sport).to be_nil
    end

    it "creates a segment for the selected sport" do
      add_source_points
      sign_in_user
      other = create(:sport)

      post workout_segments_path(workout), params: {
        segment: {
          name: "Autre sport",
          source_start_index: 0,
          source_end_index: 2,
          match_tolerance_meters: 25,
          sport_id: other.id
        }
      }

      expect(Segment.order(:id).last.sport).to eq(other)
    end

    it "rejects an invalid selection without creating a segment" do
      add_source_points
      sign_in_user

      expect do
        post workout_segments_path(workout), params: {
          segment: { name: "No selection", source_start_index: 0, source_end_index: 0 }
        }
      end.not_to change(Segment, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("doit contenir au moins deux points")
      expect(response.body).to include('value="0" name="segment[source_start_index]"')
      expect(response.body).to include('value="0" name="segment[source_end_index]"')
    end

    it "cannot select another user's workout" do
      other_workout = create(:workout)
      sign_in_user

      get new_workout_segment_path(other_workout)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "routes" do
    it "lists only the current user's routes on the routes tab" do
      own = create(:segment, :route, user:, name: "Own route")
      create(:segment, name: "Plain segment")
      create(:segment, :route, name: "Hidden route")
      sign_in_user

      get segments_path(kind: "route")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Own route")
      expect(response.body).not_to include("Plain segment")
      expect(response.body).not_to include("Hidden route")
    end

    it "still lists segments on the default tab" do
      create(:segment, :route, user:, name: "A route")
      segment = create(:segment, user:, name: "A segment")
      sign_in_user

      get segments_path

      expect(response.body).to include("A segment")
      expect(response.body).not_to include("A route")
    end

    it "renders the route creation workspace for the owner" do
      add_source_points
      sign_in_user

      get new_workout_route_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(workout_track_path(workout), 'name="route[name]"')
      expect(response.parsed_body.at_css("input#route_match_tolerance_meters")["value"]).to eq("100")
    end

    it "creates a whole-track route" do
      add_source_points
      sign_in_user

      expect do
        post workout_routes_path(workout), params: {
          route: { name: "Morning loop", description: "The whole thing", match_tolerance_meters: 25 }
        }
      end.to change(Segment, :count).by(1)

      route = Segment.order(:id).last
      expect(response).to redirect_to(segment_path(route))
      expect(route).to have_attributes(kind: "route", source_workout: workout, visibility: "private")
    end

    it "cannot create or view a route from another user's workout" do
      other_workout = create(:workout)
      sign_in_user

      get new_workout_route_path(other_workout)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "segment representations" do
    let!(:segment) { create(:segment, user:, sport:) }
    let!(:effort) { create(:segment_effort, segment:, workout: create(:workout, user:, sport:)) }

    before { sign_in_user }

    it "renders the owner page with efforts and the sport-preferred pace or speed column" do
      get segment_path(segment)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(segment.name, effort.workout.title, segment_efforts_path(segment))
      expect(response.body).to include(%(<th scope="col" class="text-end">#{I18n.t("segments.leaderboard.speed")}</th>))
    end

    it "renders the detail card as summary tiles without a ranking on a private course" do
      get segment_path(segment)

      expect(response.body).to include("allure-primary-metrics", "allure-secondary-metrics")
      expect(response.body).to include(
        I18n.t("segments.details.distance"), I18n.t("segments.details.ascent"),
        I18n.t("segments.details.efforts"), I18n.t("segments.details.participants")
      )
      expect(response.body).not_to include(I18n.t("segments.details.ranking"))
    end

    it "renders the stored elevation profile chart and its table equivalent" do
      segment.update!(elevation_profile: [
        { "d" => 0.0, "ele" => 100.0 },
        { "d" => 250.0, "ele" => 112.0 }
      ])

      get segment_path(segment)

      expect(response.body).to include(segment_chart_path(segment))
      expect(response.body).to include(I18n.t("segments.show.chart.title"))
      expect(response.body).to include(I18n.t("segments.show.chart.data"))
    end

    it "shows the unavailable state without requesting a chart when no profile exists" do
      get segment_path(segment)

      expect(response.body).not_to include(segment_chart_path(segment))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("segments.show.chart.unavailable")))
    end

    it "returns the private segment geometry" do
      get segment_track_path(segment)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/geo+json")
      expect(response.headers["Cache-Control"]).to eq("private, no-store")

      body = JSON.parse(response.body)
      expect(body).to include("type" => "FeatureCollection")
      expect(body.dig("features", 0, "geometry", "type")).to eq("LineString")
      expect(body.dig("features", 0, "geometry", "coordinates"))
        .to eq([ [ 6.4074, 45.071 ], [ 6.4092, 45.0728 ] ])
    end

    it "sends the cumulative distances hover sync needs, with no per-point metrics" do
      get segment_track_path(segment)

      properties = JSON.parse(response.body).dig("features", 0, "properties")
      expect(properties["segment_index"]).to eq(0)
      expect(properties["distance"]).to eq([ 0.0, 250.0 ])
      expect(properties.keys).to contain_exactly("segment_index", "distance")
    end

    it "renders the owner effort history and never another athlete's effort" do
      own_workout = effort.workout
      own_workout.update!(title: "Ma sortie")
      other_workout = create(:workout, user: create(:user), sport:, title: "Sortie d'un autre")

      create(:segment_effort, segment:, workout: other_workout, user: other_workout.user, sport:)

      get segment_path(segment)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(own_workout.title, segment_efforts_path(segment))
      expect(response.body).not_to include(other_workout.title)

      get segment_efforts_path(segment)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(own_workout.title)
      expect(response.body).not_to include(other_workout.title)
    end

    it "draws no progression chart for a single effort" do
      get segment_path(segment)

      expect(response.body).not_to include('data-controller="segment-progress-chart"')
    end

    it "renders the viewer's own progression, oldest first, without another athlete's effort" do
      effort.update!(started_at: 2.months.ago, elapsed_time: 300)
      later = create(:workout, user:, sport:, title: "Sortie record")
      create(:segment_effort, segment:, workout: later, started_at: 1.month.ago, elapsed_time: 280)
      other_workout = create(:workout, user: create(:user), sport:, title: "Sortie d'un autre")
      create(:segment_effort, segment:, workout: other_workout, user: other_workout.user, sport:, elapsed_time: 200)

      get segment_path(segment)

      expect(response.body).to include('data-controller="segment-progress-chart"', I18n.t("segments.progress.title"))
      payload = JSON.parse(Nokogiri::HTML(response.body)
        .at_css("[data-segment-progress-chart-payload-value]")["data-segment-progress-chart-payload-value"])
      points = payload["points"]
      expect(points.pluck("y")).to eq([ 300, 280 ])
      expect(points.pluck("place")).to eq([ 2, 1 ])
      expect(points.first["gap"]).to eq("#{I18n.t('segments.progress.places.second')} · #{I18n.t('segments.progress.gap', time: '0:20')}")
      expect(points.last).to include("title" => "Sortie record", "url" => workout_path(later), "gap" => I18n.t("segments.progress.record"))
      expect(payload["trend"]).to eq([])
      expect(response.body).not_to include(other_workout.title)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("segments.progress.gap", time: "0:20")))
    end

    it "sends the trend once the viewer has three outings" do
      now = Time.current.change(usec: 0)
      effort.update!(started_at: now - 90.days, elapsed_time: 300)
      [ [ now - 60.days, 290 ], [ now - 30.days, 280 ] ].each do |started_at, elapsed_time|
        create(:segment_effort, segment:, workout: create(:workout, user:, sport:), started_at:, elapsed_time:)
      end

      get segment_path(segment)

      payload = JSON.parse(Nokogiri::HTML(response.body)
        .at_css("[data-segment-progress-chart-payload-value]")["data-segment-progress-chart-payload-value"])
      # Under five outings the whole trend is the dotted series.
      expect(payload["trend"]).to eq([])
      expect(payload["trend_uncertain"].pluck("y").values_at(0, -1)).to eq([ 300.0, 280.0 ])
      expect(payload["trend_uncertain"].pluck("x").each_cons(2)).to all(satisfy { |a, b| a < b })
    end

    it "draws one progression chart per sport holding two efforts" do
      effort.update!(started_at: 3.months.ago, elapsed_time: 300)
      create(:segment_effort, segment:, workout: create(:workout, user:, sport:), started_at: 2.months.ago, elapsed_time: 290)
      walking = catalog_sport("walking")
      2.times do |index|
        create(:segment_effort, segment:, workout: create(:workout, user:, sport: walking), sport: walking,
                                started_at: (index + 1).weeks.ago, elapsed_time: 900 + index)
      end
      cycling = catalog_sport("cycling")
      create(:segment_effort, segment:, workout: create(:workout, user:, sport: cycling), sport: cycling, elapsed_time: 120)

      get segment_path(segment)

      charts = Nokogiri::HTML(response.body).css('[data-controller="segment-progress-chart"]')
      expect(charts.size).to eq(2)
      expect(charts.map { JSON.parse(it["data-segment-progress-chart-payload-value"])["points"].size }).to eq([ 2, 2 ])
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("segments.progress.sport_title", sport: walking.translated_name)))
    end

    it "deletes efforts and schedules a backfill when matching settings change" do
      expect do
        patch segment_path(segment), params: { segment: { match_tolerance_meters: 30 } }
      end.to change(SegmentEffort, :count).by(-1)
        .and(change { enqueued_jobs.count }.by(1))

      expect(response).to redirect_to(segment_path(segment))
      expect(segment.reload.match_tolerance_meters).to eq(30)
    end

    it "rebuilds efforts and schedules a backfill when the sport changes" do
      other = create(:sport)

      expect do
        patch segment_path(segment), params: { segment: { sport_id: other.id } }
      end.to change(SegmentEffort, :count).by(-1)
        .and have_enqueued_job(Segments::BackfillSegmentJob)

      expect(response).to redirect_to(segment_path(segment))
      expect(segment.reload.sport).to eq(other)
    end

    it "shares the segment and schedules a backfill for other users' workouts" do
      # A share enqueues a backfill for other users' past workouts and must not
      # delete the existing efforts; eligibility follows on read.
      expect do
        patch segment_path(segment), params: { segment: { visibility: "public" } }
      end.to have_enqueued_job(Segments::BackfillSegmentJob)

      expect(response).to redirect_to(segment_path(segment))
      expect(segment.reload).to have_attributes(visibility: "public")
      expect(SegmentEffort.where(segment:).count).to eq(1)
    end
  end

  describe "shared course visibility" do
    let(:owner) { create(:user) }
    let(:viewer) { create(:user) }
    let!(:source) { create(:workout, user: owner, sport:, title: "Secret source workout") }
    let!(:segment) { create(:segment, user: owner, sport:, source_workout: source) }

    def sign_in_viewer
      post session_path, params: { email_address: viewer.email_address, password: "allure-test-password" }
    end

    it "404s another user while private" do
      sign_in_viewer

      get segment_path(segment)
      expect(response).to have_http_status(:not_found)

      get segment_track_path(segment)
      expect(response).to have_http_status(:not_found)
    end

    it "redirects an anonymous visitor to sign-in while private" do
      get segment_path(segment)
      expect(response).to redirect_to(new_session_path)

      get segment_track_path(segment)
      expect(response).to redirect_to(new_session_path)
    end

    context "when public" do
      before { segment.update!(visibility: "public") }

      it "renders the course to a signed-in non-owner without owner-only blocks" do
        sign_in_viewer
        get segment_path(segment)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(segment.name)
        expect(response.body).to include(segment_track_path(segment))
        expect(response.body).to include(I18n.t("segments.details.descent"), I18n.t("segments.details.participants"))
        expect(response.body).not_to include("Secret source workout")
        expect(response.body).not_to include(edit_segment_path(segment))
        expect(response.body).not_to include(I18n.t("segments.show.delete"))
      end

      it "counts only the participants the viewer sees ranked, never an unpublished effort" do
        athlete = create(:user)
        workout = create(:workout, user: athlete, sport:)
        create(:segment_effort, segment:, workout:, user: athlete, sport:)
        participants = %r{<dt>#{I18n.t("segments.details.participants")}</dt>\s*<dd>(\d+)</dd>}

        sign_in_viewer
        get segment_path(segment)
        expect(response.body[participants, 1]).to eq("0")

        profile = build(:publishing_profile, user: athlete)
        profile.settings = profile.settings.merge("route" => true)
        create(:workout_publication, workout:, publishing_profile: profile, status: "active")

        get segment_path(segment)
        expect(response.body[participants, 1]).to eq("1")
      end

      it "serves the geometry to a signed-in non-owner" do
        sign_in_viewer
        get segment_track_path(segment)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/geo+json")
      end

      it "hides the owner's effort history from a signed-in non-owner" do
        create(:segment_effort, segment:, workout: create(:workout, user: owner, sport:, title: "Owner private effort"))
        sign_in_viewer

        get segment_path(segment)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Secret source workout")
        expect(response.body).not_to include("Owner private effort")
        expect(response.body).not_to include(I18n.t("segments.show.edit"))
      end

      it "shows the all-sports label for a multi-sport course" do
        segment.update!(sport: nil)
        sign_in_viewer

        get segment_path(segment)

        expect(response.body).to include(I18n.t("segments.details.all_sports"))
      end
    end

    context "when followers_only" do
      before do
        segment.update!(visibility: "followers_only")
        create(:local_actor, user: owner)
        create(:local_actor, user: viewer)
      end

      it "404s a signed-in non-follower and redirects an anonymous visitor" do
        sign_in_viewer

        get segment_path(segment)
        expect(response).to have_http_status(:not_found)

        get segment_track_path(segment)
        expect(response).to have_http_status(:not_found)

        delete session_path
        get segment_path(segment)
        expect(response).to redirect_to(new_session_path)
      end

      it "allows an accepted local follower" do
        create(:following, :accepted, follower_actor: viewer.actor, followed_actor: owner.actor)
        sign_in_viewer

        get segment_path(segment)
        expect(response).to have_http_status(:ok)

        get segment_track_path(segment)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "sharing through a privacy zone" do
    let!(:segment) { create(:segment, user:, sport:) }

    it "requires an acknowledgment before sharing an intersecting corridor" do
      create(:privacy_zone, user:)
      sign_in_user

      patch segment_path(segment), params: { segment: { visibility: "public" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("segments.form.corridor.confirm"))
      expect(segment.reload).to have_attributes(visibility: "private", privacy_zone_acknowledged_at: nil)
    end

    it "shares the corridor once the owner acknowledges" do
      create(:privacy_zone, user:)
      sign_in_user

      patch segment_path(segment), params: { segment: { visibility: "public", acknowledge_privacy_zones: "1" } }

      expect(response).to redirect_to(segment_path(segment))
      expect(segment.reload.visibility).to eq("public")
      expect(segment.reload.privacy_zone_acknowledged_at).to be_present
    end

    it "rolls a failed tolerance update back completely" do
      create(:privacy_zone, user:)
      segment.update_columns(visibility: "public", privacy_zone_acknowledged_at: Time.current)
      effort = create(:segment_effort, segment:, workout: create(:workout, user:, sport:))
      sign_in_user

      patch segment_path(segment), params: { segment: { match_tolerance_meters: 30 } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(segment.reload.match_tolerance_meters).to eq(25)
      expect(SegmentEffort.exists?(effort.id)).to be(true)
    end
  end
end
