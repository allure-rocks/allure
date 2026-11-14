# frozen_string_literal: true

require "rails_helper"
require "digest"

RSpec.describe "Allure::Withings" do
  let(:base) { "https://scalews.withings.net" }
  let(:epoch) { 1_735_689_600 } # 2025-01-01T00:00:00Z
  let(:http) { Allure::Withings::Http.new(min_interval: 0) }

  def envelope(status, body)
    JSON.generate({ "status" => status, "body" => body })
  end

  describe Allure::Withings::Session do
    it "signs in with the Health Mate form and the MD5 digest of the password" do
      stub = stub_request(:post, "#{base}/cgi-bin/auth")
        .with(body: {
          "email" => "rider@example.test", "duration" => "900",
          "hash" => Digest::MD5.hexdigest("secret"), "callctx" => "foreground",
          "action" => "login", "appname" => "wiscaleNG", "appfm" => "ios", "appliver" => "4050301"
        })
        .to_return(body: envelope(0, { "sessionid" => "S1", "account" => [ { "id" => 42 } ] }))

      signed_in = described_class.new(http:).sign_in(email: "rider@example.test", password: "secret")

      expect(stub).to have_been_requested
      expect(signed_in).to have_attributes(session_id: "S1", account_id: 42)
    end

    it "reports refused credentials (status 100)" do
      stub_request(:post, "#{base}/cgi-bin/auth").to_return(body: envelope(100, nil))

      expect { described_class.new(http:).sign_in(email: "a@b.test", password: "x") }
        .to raise_error(Allure::Withings::Error::InvalidCredentials)
    end

    it "carries an unknown status instead of guessing its meaning" do
      stub_request(:post, "#{base}/cgi-bin/auth").to_return(body: envelope(2553, nil))

      expect { described_class.new(http:).sign_in(email: "a@b.test", password: "x") }
        .to raise_error(Allure::Withings::Error::ApiStatus) { |error| expect(error.status).to eq(2553) }
    end

    it "refuses a login answer without a session id" do
      stub_request(:post, "#{base}/cgi-bin/auth").to_return(body: envelope(0, { "account" => [ { "id" => 42 } ] }))

      expect { described_class.new(http:).sign_in(email: "a@b.test", password: "x") }
        .to raise_error(Allure::Withings::Error::Unavailable)
    end

    it "reads the account's users" do
      signed_in = Allure::Withings::Session::SignedIn.new(session_id: "S1", account_id: 42, body: {})
      stub_request(:post, "#{base}/cgi-bin/account")
        .with(body: hash_including("action" => "getuserslist", "accountid" => "42", "sessionid" => "S1"))
        .to_return(body: envelope(0, { "users" => [ { "id" => 7 } ] }))

      expect(described_class.new(http:).users(signed_in)).to eq([ { "id" => 7 } ])
    end
  end

  describe Allure::Withings::Client do
    subject(:client) { described_class.new(session_id: "S1", user_id: 7, http:) }

    let(:positioned) do
      {
        "id" => 501, "subcategory" => 2, "startdate" => epoch, "enddate" => epoch + 3600,
        "gps" => { "distance" => 5000, "avg_speed" => 1.4 },
        "data" => { "hr_average" => 120, "calories" => 320 }
      }
    end
    let(:indoor) do
      { "id" => 502, "subcategory" => 307, "startdate" => epoch + 86_400, "enddate" => epoch + 90_000, "gps" => nil,
        "data" => { "hr_average" => 130 } }
    end
    let(:steps) do
      { "id" => 503, "startdate" => epoch + 7200, "enddate" => epoch + 9000, "category" => 128, "gps" => nil }
    end
    let(:night) do
      { "id" => 504, "startdate" => epoch + 86_400, "enddate" => epoch + 110_000, "gps" => nil,
        "data" => { "hr_average" => 60, "deepsleepduration" => 5000, "night_events" => [] } }
    end

    it "lists the workouts of the range, walking 30-day windows, newest first" do
      stub_request(:post, "#{base}/cgi-bin/v2/activity")
        .with(body: hash_including("startdateymd" => "2025-01-01", "enddateymd" => "2025-01-31"))
        .to_return(body: envelope(0, { "series" => [ positioned, steps ] }))
      stub_request(:post, "#{base}/cgi-bin/v2/activity")
        .with(body: hash_including("startdateymd" => "2024-12-02", "enddateymd" => "2024-12-31"))
        .to_return(body: envelope(0, { "series" => [ indoor.merge("startdate" => epoch - 86_400) ] }))

      activities = client.activities(from: Date.new(2024, 12, 2), to: Date.new(2025, 1, 31))

      expect(activities.map(&:id)).to eq([ 503, 501, 502 ])
      expect(activities.first).to have_attributes(auto_detected?: true)
      expect(activities.second).to have_attributes(
        started_at: Time.at(epoch).utc, ended_at: Time.at(epoch + 3600).utc,
        category: 2, positioned?: true, auto_detected?: false
      )
    end

    it "reads the workout category from the item's subcategory, with category as the fallback" do
      stub_request(:post, "#{base}/cgi-bin/v2/activity")
        .to_return(body: envelope(0, { "series" => [ positioned.merge("category" => 36), indoor ] }))

      activities = client.activities_in_window(from: Date.new(2025, 1, 1), to: Date.new(2025, 1, 2))

      # The private listing names the public enum `subcategory` (observed
      # 2026-11-01); `category` only answers when present.
      expect(activities.first.category).to eq(2)
      expect(activities.second.category).to eq(307)
    end

    it "parses an indoor workout, an auto-detected step session and a sleep summary" do
      stub_request(:post, "#{base}/cgi-bin/v2/activity")
        .to_return(body: envelope(0, { "series" => [ indoor, steps, night ] }))

      activities = client.activities_in_window(from: Date.new(2025, 1, 1), to: Date.new(2025, 1, 2))

      expect(activities.first).to have_attributes(positioned?: false, auto_detected?: false, category: 307)
      expect(activities.second).to have_attributes(auto_detected?: true, gps: nil, data: nil)
      expect(activities.third).to have_attributes(sleep?: true, positioned?: false)
      expect(activities.first.raw).to eq(indoor)
      expect(activities.first.sleep?).to be(false)
    end

    it "reads the intraday companion of a session" do
      stub_request(:post, "#{base}/cgi-bin/v2/measure")
        .with(body: hash_including("action" => "getintradayactivity", "startdate" => epoch.to_s,
                                    "enddate" => (epoch + 3600).to_s, "sessionid" => "S1"))
        .to_return(body: envelope(0, { "series" => [ { "epoch" => epoch } ] }))

      intraday = client.intraday_activity(Time.at(epoch).utc, Time.at(epoch + 3600).utc)

      expect(intraday.dig("body", "series")).to eq([ { "epoch" => epoch } ])
    end

    it "reads the two series of a session" do
      location = stub_request(:post, "#{base}/cgi-bin/v2/measure")
        .with(body: hash_including("action" => "getvasistas", "meastype" => "98,99,97,72,96,101,100",
                                    "vasistas_category" => "location", "startdate" => epoch.to_s,
                                    "enddate" => (epoch + 3600).to_s))
        .to_return(body: envelope(0, { "series" => [ { "dates" => [ epoch ], "vasistas" => [ [ 45.1, 5.2 ] ] } ] }))
      heart_rate = stub_request(:post, "#{base}/cgi-bin/v2/measure")
        .with(body: hash_including("meastype" => "11,43,73,89", "vasistas_category" => "hr"))
        .to_return(body: envelope(0, { "series" => [ { "dates" => [ epoch ], "vasistas" => [ [ 110 ] ] } ] }))

      started_at = Time.at(epoch).utc
      ended_at = Time.at(epoch + 3600).utc
      expect(client.location_series(started_at, ended_at)).to have_attributes(dates: [ epoch ], rows: [ [ 45.1, 5.2 ] ])
      expect(client.heart_rate_series(started_at, ended_at)).to have_attributes(rows: [ [ 110 ] ])
      expect(location).to have_been_requested
      expect(heart_rate).to have_been_requested
    end

    it "answers an empty series when nothing was recorded" do
      stub_request(:post, "#{base}/cgi-bin/v2/measure")
        .to_return(body: envelope(0, { "series" => [] }))

      series = client.heart_rate_series(Time.at(epoch).utc, Time.at(epoch + 60).utc)
      expect(series).to have_attributes(dates: [], rows: [])
    end

    it "carries an unknown status on an authenticated call" do
      stub_request(:post, "#{base}/cgi-bin/v2/activity").to_return(body: envelope(2553, nil))

      expect { client.activities_in_window(from: Date.new(2025, 1, 1), to: Date.new(2025, 1, 2)) }
        .to raise_error(Allure::Withings::Error::ApiStatus) { |error| expect(error.status).to eq(2553) }
    end
  end

  describe Allure::Withings::TcxWriter do
    let(:activity) do
      Allure::Withings::Client::Activity.new(
        id: 501, started_at: Time.at(epoch).utc, ended_at: Time.at(epoch + 3600).utc,
        category: 2, gps: { "distance" => 5000 }, data: { "calories" => 320 }
      )
    end
    let(:location) do
      Allure::Withings::Client::Series.new(
        dates: [ epoch, epoch + 10, epoch + 20 ],
        rows: [ [ 45.1, 5.2, 83.7 ], [ 45.1001, 5.2001, 84.2 ], [ 45.1002, 5.2002, -20_000.0 ] ]
      )
    end
    let(:heart_rate) do
      Allure::Withings::Client::Series.new(dates: [ epoch + 9, epoch + 31 ], rows: [ [ 110 ], [ 112 ] ])
    end

    def build(activity: self.activity, location: self.location, heart_rate: self.heart_rate)
      described_class.build(activity:, location:, heart_rate:)
    end

    it "builds the deterministic positioned document, merging the nearest heart rate within 10 s" do
      document = Nokogiri::XML(build)

      expect(document.root.name).to eq("TrainingCenterDatabase")
      activity_node = document.at_css("Activities > Activity")
      expect(activity_node["Sport"]).to eq("Running")
      expect(activity_node.at_css("Lap")["StartTime"]).to eq("2025-01-01T00:00:00Z")
      expect(activity_node.at_css("Lap > TotalTimeSeconds").text).to eq("3600")
      expect(activity_node.at_css("Lap > DistanceMeters").text).to eq("5000.0")
      expect(activity_node.at_css("Lap > Calories").text).to eq("320")
      expect(document.at_css("Author > Name").text).to eq("Withings")

      points = activity_node.css("Track > Trackpoint")
      expect(points.length).to eq(3)
      expect(points[0].at_css("Position > LatitudeDegrees").text).to eq("45.1000000")
      expect(points[0].at_css("Position > LongitudeDegrees").text).to eq("5.2000000")
      # The elevation column, with the sentinel dropped: 83.7 m kept,
      # -20 000 written as no altitude at all.
      expect(points[0].at_css("AltitudeMeters").text).to eq("83.7")
      expect(points[1].at_css("AltitudeMeters").text).to eq("84.2")
      expect(points[2].at_css("AltitudeMeters")).to be_nil
      # 9 s away: kept. 11 s away from the last sample: dropped.
      expect(points[0].at_css("HeartRateBpm > Value").text).to eq("110")
      expect(points[1].at_css("HeartRateBpm > Value").text).to eq("110")
      expect(points[2].at_css("HeartRateBpm")).to be_nil
      expect(points[2].at_css("Position > LatitudeDegrees").text).to eq("45.1002000")
    end

    it "builds the same bytes twice" do
      expect(build).to eq(build)
    end

    it "writes an indoor session as heart-rate trackpoints without a position" do
      indoor = Allure::Withings::Client::Activity.new(
        id: 502, started_at: Time.at(epoch).utc, ended_at: Time.at(epoch + 1800).utc,
        category: 307, gps: nil, data: { "calories" => 200, "distance" => 4800 }
      )
      document = Nokogiri::XML(build(activity: indoor, location: Allure::Withings::Client::Series.empty, heart_rate:))

      points = document.css("Track > Trackpoint")
      expect(points.length).to eq(2)
      expect(points.map { |point| point.at_css("Position") }).to all(be_nil)
      expect(points.map { |point| point.at_css("HeartRateBpm > Value").text }).to eq(%w[110 112])
      expect(document.at_css("Lap > DistanceMeters").text).to eq("4800.0")
      expect(document.at_css("Lap > TotalTimeSeconds").text).to eq("1800")
    end

    it "refuses a session that recorded nothing" do
      expect { build(location: Allure::Withings::Client::Series.empty,
                     heart_rate: Allure::Withings::Client::Series.empty) }
        .to raise_error(Allure::Withings::Error::NoSamples)
    end

    it "refuses a session with fewer than two usable samples" do
      sparse = Allure::Withings::Client::Series.new(dates: [ epoch ], rows: [ [ 45.1, 5.2 ] ])
      one = Allure::Withings::Client::Series.new(dates: [ epoch ], rows: [ [ 110 ] ])

      expect { build(location: sparse, heart_rate: one) }
        .to raise_error(Allure::Withings::Error::NoSamples)
    end

    it "falls back to the heart-rate timeline when the location answer is sparse" do
      # A GPS session whose track did not reach the cloud: one fix is not a
      # route, so the heart-rate samples become a positionless recording
      # and no position is invented (observed 2026-11-01).
      sparse = Allure::Withings::Client::Series.new(dates: [ epoch ], rows: [ [ 45.1, 5.2 ] ])

      document = Nokogiri::XML(build(location: sparse, heart_rate:))

      points = document.css("Track > Trackpoint")
      expect(points.length).to eq(2)
      expect(points.map { |point| point.at_css("Position") }).to all(be_nil)
      expect(points.map { |point| point.at_css("HeartRateBpm > Value").text }).to eq(%w[110 112])
    end

    it "round trips through Allure's own TCX parser" do
      track = Allure::Tcx::Parser.new.parse(StringIO.new(build))
      expect(track).to have_attributes(creator: "Withings", positioned?: true)
      expect(track.points_count).to eq(3)
      expect(track.segments.first.first_point).to have_attributes(heart_rate: 110, elevation: 83.7)
      expect(track.laps.first).to have_attributes(distance: 5000.0)
      expect(track.activity_signals.map(&:value)).to eq(%w[run])

      indoor = Allure::Withings::Client::Activity.new(
        id: 502, started_at: Time.at(epoch).utc, ended_at: Time.at(epoch + 1800).utc, category: 307
      )
      indoor_track = Allure::Tcx::Parser.new.parse(
        StringIO.new(build(activity: indoor, location: Allure::Withings::Client::Series.empty, heart_rate:))
      )
      expect(indoor_track).to have_attributes(positioned?: false, points_count: 2)
      expect(indoor_track.segments.first.first_point).to have_attributes(latitude: nil, heart_rate: 110)
    end

    it "analyses through the ordinary analyzer as a positioned and a positionless recording" do
      metrics = Allure::Gpx::Analyzer.new(
        stopped_speed_threshold_km_h: 1.0, records_elevation: false, grade_adjusted_pace: false
      ).analyze(Allure::Tcx::Parser.new.parse(StringIO.new(build)))
      expect(metrics.distance).to be_positive
      expect(metrics.duration).to eq(20)

      indoor = Allure::Withings::Client::Activity.new(
        id: 502, started_at: Time.at(epoch).utc, ended_at: Time.at(epoch + 22).utc, category: 307
      )
      indoor_metrics = Allure::Gpx::Analyzer.new(
        stopped_speed_threshold_km_h: 1.0, records_elevation: false, grade_adjusted_pace: false
      ).analyze(Allure::Tcx::Parser.new.parse(
        StringIO.new(build(activity: indoor, location: Allure::Withings::Client::Series.empty, heart_rate:))
      ))
      expect(indoor_metrics.distance).to eq(0)
      expect(indoor_metrics.duration).to eq(22)
    end
  end

  describe Allure::Withings::SportMapping do
    it "maps the categories Allure's catalog has a sport for" do
      expect(described_class.slug(1)).to eq("walking")
      expect(described_class.slug(2)).to eq("running")
      expect(described_class.slug(3)).to eq("hiking")
      expect(described_class.slug(6)).to eq("cycling")
      expect(described_class.slug(7)).to eq("pool_swimming")
      expect(described_class.slug(187)).to eq("rowing")
      expect(described_class.slug(307)).to eq("running")
      expect(described_class.slug(308)).to eq("cycling")
    end

    it "leaves categories without an equivalent to the fallback sport" do
      expect(described_class.slug(8)).to be_nil
      expect(described_class.slug(34)).to be_nil
      expect(described_class.slug(36)).to be_nil
    end

    it "names the TCX sport only where the parser resolves it" do
      expect(described_class.sport_name(2)).to eq("Running")
      expect(described_class.sport_name(6)).to eq("Biking")
      expect(described_class.sport_name(307)).to eq("Other")
      expect(described_class.sport_name(nil)).to eq("Other")
    end

    it "knows the category names" do
      expect(described_class.name(128)).to eq("No activity")
      expect(described_class.name(999)).to eq("category 999")
    end
  end
end
