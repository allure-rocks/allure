# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportConnections::Providers::GarminConnect do
  subject(:provider) { described_class.new(connection) }

  let(:user) { create(:user) }
  let(:connection) do
    create(:import_connection, :linked, user:, token_expires_at: 1.day.from_now,
                                        credentials: { "di_token" => "a1", "di_refresh_token" => "r1", "di_client_id" => "CID" })
  end
  let(:api) { "https://connectapi.garmin.com" }
  let(:list_url) { %r{\A#{api}/activitylist-service/activities/search/activities} }
  let(:gpx) { Rails.root.join("spec/fixtures/gpx/galibier.gpx").binread }
  # An indoor ride: sport and sub-sport with cumulative distance, speed and
  # power, and not one position (PLAN_NO_GPS.md).
  let(:indoor_fit) do
    start = Time.utc(2026, 6, 2, 18, 0, 0)
    build_fit(sport: 2, sub_sport: 6, calories: 420, points: [
      { time: start, hr: 118, cadence: 82, power: 190, distance: 0.0, speed: 8.0 },
      { time: start + 300, hr: 132, cadence: 85, power: 210, distance: 2_500.0, speed: 8.4 },
      { time: start + 600, hr: 141, cadence: 87, power: 225, distance: 5_000.0, speed: 8.2 }
    ])
  end
  let(:items) do
    [
      { activityId: 101, activityName: "Galibier", startTimeGMT: "2026-06-01 08:00:00",
        activityType: { typeKey: "road_biking" }, hasPolyline: true, manualActivity: false },
      { activityId: 102, activityName: "Home trainer", startTimeGMT: "2026-06-02 18:00:00",
        activityType: { typeKey: "indoor_cycling" }, hasPolyline: false, manualActivity: false }
    ]
  end

  def zip_of(name, content)
    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry(name)
      zip.write(content)
    end.string
  end

  before do
    allow_any_instance_of(Allure::GarminConnect::Client).to receive(:throttle) # rubocop:disable RSpec/AnyInstance
    stub_request(:get, list_url).to_return(status: 200, body: items.to_json)
    stub_request(:get, "#{api}/download-service/files/activity/101")
      .to_return(status: 200, body: zip_of("101_ACTIVITY.gpx", gpx))
    # The indoor activity keeps its file: it is imported as a positionless
    # recording, never skipped for lacking a GPS track (PLAN_NO_GPS.md §8).
    stub_request(:get, "#{api}/download-service/files/activity/102")
      .to_return(status: 200, body: zip_of("102_ACTIVITY.fit", indoor_fit))
    stub_request(:get, "#{api}/gear-service/gear/filterGear").with(query: { "userProfilePk" => "151984342" })
      .to_return(status: 200, body: [ { uuid: "g-1", displayName: "Canyon", gearTypeName: "Bike",
                                        gearMakeName: "Canyon", gearModelName: "Ultimate", gearStatusName: "active" } ].to_json)
  end

  it_behaves_like "an import provider" do
    let(:listed_activity) { provider.list(from: Time.utc(2026, 6, 1), to: Time.utc(2026, 6, 30)).first }
  end

  it "maps the listing, with geometry known before any fetch" do
    activities = provider.list(from: Time.utc(2026, 6, 1), to: Time.utc(2026, 6, 30))

    expect(activities.map(&:external_id)).to eq(%w[101 102])
    expect(activities.first).to have_attributes(name: "Galibier", started_at: Time.utc(2026, 6, 1, 8),
                                                sport_hint: "road_biking", geometry: true)
    expect(activities.last.geometry).to be(false)
    expect(a_request(:get, list_url).with(query: hash_including("startDate" => "2026-06-01", "endDate" => "2026-06-30")))
      .to have_been_made
  end

  it "extracts the original file from the download" do
    fetched = provider.fetch(provider.list(from: Time.utc(2026, 6, 1), to: Time.utc(2026, 6, 30)).first)

    expect(fetched.filename).to eq("garmin-101.gpx")
    expect(fetched.io.read).to eq(gpx)
    expect(fetched.title).to eq("Galibier")
  ensure
    fetched&.io&.close!
  end

  it "takes a download that is not a ZIP as the FIT itself" do
    stub_request(:get, "#{api}/download-service/files/activity/101").to_return(status: 200, body: ".FIT-bytes")

    fetched = provider.fetch(Allure::RemoteImports::RemoteActivity.new(external_id: "101", name: nil, started_at: nil,
                                                                       sport_hint: nil, geometry: true))

    expect(fetched.filename).to eq("garmin-101.fit")
  ensure
    fetched&.io&.close!
  end

  it "persists the rotated token as soon as Garmin refreshes it" do
    connection.update!(token_expires_at: 5.minutes.from_now)
    stub_request(:post, "https://diauth.garmin.com/di-oauth2-service/oauth/token")
      .with(body: hash_including("refresh_token" => "r1"))
      .to_return(status: 200, body: { access_token: "a2", refresh_token: "r2" }.to_json)

    provider.list(from: Time.utc(2026, 6, 1), to: Time.utc(2026, 6, 30))

    expect(connection.reload.credentials).to include("di_token" => "a2", "di_refresh_token" => "r2")
  end

  it "maps a refused token to an AuthError and a 429 to a pause" do
    stub_request(:get, list_url).to_return(status: 401)
    stub_request(:post, "https://diauth.garmin.com/di-oauth2-service/oauth/token").to_return(status: 400)
    expect { provider.list(from: Time.utc(2026, 6, 1), to: Time.utc(2026, 6, 2)) }
      .to raise_error(Allure::RemoteImports::Error::AuthError)

    stub_request(:get, list_url).to_return(status: 429)
    expect { described_class.new(connection).list(from: Time.utc(2026, 6, 1), to: Time.utc(2026, 6, 2)) }
      .to raise_error(Allure::RemoteImports::Error::RateLimited) { |error| expect(error.retry_at).to be > 10.minutes.from_now }
  end

  it "maps the gear" do
    expect(provider.equipment.sole).to have_attributes(external_id: "g-1", name: "Canyon", kind: "bike", active: true)
  end

  it "imports through the remote batch job end to end, indoor activity included" do
    with_remote_import_enabled do
      allow(Workouts::RenderRouteImageJob).to receive(:perform_later)
      allow(Segments::MatchWorkoutJob).to receive(:perform_later)
      connection.update!(fallback_sport: catalog_sport("cycling"))
      batch = create(:workout_import_batch, user:, sport: nil, source: "garmin_connect", import_connection: connection,
                                            range_from: Date.new(2026, 6, 1), range_to: Date.new(2026, 6, 30))

      expect { Workouts::RemoteImportBatchJob.perform_now(batch) }.to change(Workout, :count).by(2)

      expect(batch.reload).to have_attributes(status: "completed", imported_entries: 2, skipped_entries: 0)
      outdoor, indoor = user.workouts.order(:external_id).to_a
      expect(outdoor).to have_attributes(external_id: "101", import_connection: connection, title: "Galibier")
      expect(indoor).to have_attributes(external_id: "102", import_connection: connection, title: "Home trainer")
      expect(indoor).not_to be_positioned
      expect(indoor.distance).to eq(5_000.0)
      expect(indoor.average_power).to eq(208)
      expect(indoor.track_segments.sole).not_to be_positioned
    end
  end
end
