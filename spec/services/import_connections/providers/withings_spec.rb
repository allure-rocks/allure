# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportConnections::Providers::Withings do
  subject(:provider) { described_class.new(connection) }

  let(:base) { "https://scalews.withings.net" }
  let(:epoch) { 1_735_689_600 }
  let(:connection) do
    create(:import_connection, :linked, provider: "withings", external_account_id: "7",
                                        external_account_name: "rider@example.test",
                                        credentials: { "sessionid" => "S1", "userid" => 7 })
  end
  let(:positioned) do
    { "id" => 501, "subcategory" => 2, "startdate" => epoch, "enddate" => epoch + 3600,
      "gps" => { "distance" => 5000 }, "data" => { "hr_average" => 120, "calories" => 320 } }
  end
  let(:indoor) do
    { "id" => 502, "subcategory" => 307, "startdate" => epoch + 86_400, "enddate" => epoch + 90_000,
      "gps" => nil, "data" => { "hr_average" => 130 } }
  end
  let(:night) do
    { "id" => 503, "startdate" => epoch + 110_000, "enddate" => epoch + 130_000,
      "gps" => nil, "data" => { "hr_average" => 60, "deepsleepduration" => 5000 } }
  end
  let(:steps) do
    { "id" => 504, "startdate" => epoch + 140_000, "enddate" => epoch + 141_000,
      "gps" => nil, "data" => { "calories" => 80 } }
  end
  let(:listed_activity) do
    remote_activity("501", started_at: Time.at(epoch).utc, ended_at: Time.at(epoch + 3600).utc,
                    sport_hint: 2, name: nil)
  end

  def envelope(status, body)
    JSON.generate({ "status" => status, "body" => body })
  end

  def activity_endpoint(items)
    stub_request(:post, "#{base}/cgi-bin/v2/activity")
      .to_return(body: envelope(0, { "series" => items }))
  end

  def series_endpoint(category, dates:, rows:)
    stub_request(:post, "#{base}/cgi-bin/v2/measure")
      .with(body: hash_including("vasistas_category" => category, "sessionid" => "S1", "userid" => "7"))
      .to_return(body: envelope(0, { "series" => [ { "dates" => dates, "vasistas" => rows } ] }))
  end

  before do
    stub_const("Allure::Withings::Http::MIN_INTERVAL", 0)
    activity_endpoint([ positioned ])
    series_endpoint("location", dates: [ epoch, epoch + 10 ], rows: [ [ 45.1, 5.2, 83.7 ], [ 45.1001, 5.2001, 84.2 ] ])
    series_endpoint("hr", dates: [ epoch + 9, epoch + 20 ], rows: [ [ 110 ], [ 112 ] ])
  end

  it_behaves_like "an import provider"

  it "lists the range's sessions, skipping sleep and summaries with nothing to record" do
    activity_endpoint([ positioned, indoor, night, steps ])

    activities = provider.list(from: Time.at(epoch).utc, to: Time.at(epoch + 200_000).utc)

    expect(activities).to contain_exactly(
      have_attributes(external_id: "501", started_at: Time.at(epoch).utc, ended_at: Time.at(epoch + 3600).utc,
                      sport_hint: 2, geometry: true, manual: false),
      have_attributes(external_id: "502", sport_hint: 307, geometry: false)
    )
  end

  it "round trips the listed end through an entry's metadata" do
    activity_endpoint([ positioned ])
    activity = provider.list(from: Time.at(epoch).utc, to: Time.at(epoch + 3600).utc).sole

    rebuilt = Allure::RemoteImports::RemoteActivity.from_metadata(activity.external_id, activity.metadata)

    expect(rebuilt).to have_attributes(ended_at: Time.at(epoch + 3600).utc, sport_hint: 2, geometry: true)
  end

  it "fetches the synthesized TCX with the declared sport" do
    fetched = provider.fetch(listed_activity)

    expect(fetched).to have_attributes(filename: "withings-501.tcx", declared_sport: "running",
                                       title: nil, device_name: nil)
    expect(Allure::ImportFormat.detect(fetched.io)).to eq(Allure::ImportFormat::TCX)
    track = Allure::Tcx::Parser.new.parse(fetched.io)
    expect(track).to have_attributes(positioned?: true, points_count: 2)
    expect(track.segments.first.first_point).to have_attributes(elevation: 83.7, heart_rate: 110)
  ensure
    fetched&.io&.close
  end

  it "answers nothing-recorded as a skipped fetch when positionless sessions import" do
    connection.update!(positioned_only: false)
    series_endpoint("location", dates: [], rows: [])
    series_endpoint("hr", dates: [], rows: [])

    expect { provider.fetch(listed_activity) }.to raise_error(Allure::RemoteImports::Error::NotFound)
  end

  it "answers a sparse location answer as no geometry when the connection imports positioned sessions only" do
    expect(connection.positioned_only?).to be(true)
    series_endpoint("location", dates: [ epoch ], rows: [ [ 45.1, 5.2, -20_000 ] ])

    expect { provider.fetch(listed_activity) }.to raise_error(Allure::RemoteImports::Error::NoGeometry)
  end

  it "falls back to the heart-rate timeline for a sparse location answer when positionless sessions import" do
    connection.update!(positioned_only: false)
    series_endpoint("location", dates: [ epoch ], rows: [ [ 45.1, 5.2, -20_000 ] ])

    fetched = provider.fetch(listed_activity)

    track = Allure::Tcx::Parser.new.parse(fetched.io)
    expect(track).to have_attributes(positioned?: false, points_count: 2)
  ensure
    fetched&.io&.close
  end

  [ 250, 501 ].each do |status|
    it "answers a dead session (status #{status}) as a natural end" do
      stub_request(:post, "#{base}/cgi-bin/v2/activity").to_return(body: envelope(status, nil))

      expect { provider.list(from: Time.at(epoch).utc, to: Time.at(epoch + 3600).utc) }
        .to raise_error(Allure::RemoteImports::Error::SessionEnded)
    end
  end

  it "answers an unknown status as an authentication failure" do
    stub_request(:post, "#{base}/cgi-bin/v2/activity").to_return(body: envelope(2553, nil))

    expect { provider.list(from: Time.at(epoch).utc, to: Time.at(epoch + 3600).utc) }
      .to raise_error(Allure::RemoteImports::Error::AuthError)
  end

  it "verifies the session with one authenticated listing" do
    activity_endpoint([])

    expect(provider.verify!).to be(true)
  end

  it "has no equipment" do
    expect(provider.equipment).to eq([])
  end
end
