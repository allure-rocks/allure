# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Allure::Zwift" do
  let(:auth_base) { "https://secure.zwift.com" }
  let(:token_url) { "#{auth_base}#{Allure::Zwift::Auth::TOKEN_PATH}" }
  let(:logout_url) { "#{auth_base}#{Allure::Zwift::Auth::LOGOUT_PATH}" }
  let(:api_base) { "https://us-or-rly101.zwift.com" }
  let(:http) { Allure::Zwift::Http.new(min_interval: 0) }

  def token_body(overrides = {})
    JSON.generate({
      "access_token" => "A1", "refresh_token" => "R1", "expires_in" => 3_600,
      "refresh_expires_in" => 691_200, "token_type" => "Bearer"
    }.merge(overrides))
  end

  def activity_row(id:, started_at:, **overrides)
    {
      "id" => id, "startDate" => started_at, "name" => "Watopia ride", "sport" => "CYCLING",
      "worldId" => 1, "distanceInMeters" => 20_000, "duration" => 45,
      "fitFileBucket" => "s3-fit-prd-zwift", "fitFileKey" => "fit/#{id}.fit"
    }.merge(overrides.transform_keys(&:to_s))
  end

  describe Allure::Zwift::Auth do
    it "signs in with the password grant and reads the observed lifetimes" do
      stub = stub_request(:post, token_url)
        .with(body: { "client_id" => "Zwift_Mobile_Link", "grant_type" => "password",
                      "username" => "rider@example.test", "password" => "secret" })
        .to_return(body: token_body)

      tokens = described_class.new(http:).sign_in(email: "rider@example.test", password: "secret")

      expect(stub).to have_been_requested
      expect(tokens).to have_attributes(
        access_token: "A1", refresh_token: "R1",
        expires_in: 3_600, refresh_expires_in: 691_200
      )
      expect(tokens.expires_at).to be_within(5).of(Time.now + 3_600)
      expect(tokens.refresh_expires_at).to be_within(5).of(Time.now + 691_200)
    end

    it "reads a millisecond expires_in as milliseconds" do
      stub_request(:post, token_url)
        .to_return(body: token_body("expires_in" => 86_400_000, "refresh_expires_in" => 1_800_000))

      tokens = described_class.new(http:).sign_in(email: "a@b.test", password: "x")

      expect(tokens.expires_at).to be_within(5).of(Time.now + 86_400)
      expect(tokens.refresh_expires_at).to be_within(5).of(Time.now + 1_800)
    end

    it "refreshes and keeps a rotated refresh token" do
      stub = stub_request(:post, token_url)
        .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "R1"))
        .to_return(body: token_body("access_token" => "A2", "refresh_token" => "R2", "expires_in" => 3_600_000))

      tokens = described_class.new(http:).refresh(refresh_token: "R1")

      expect(stub).to have_been_requested
      expect(tokens).to have_attributes(access_token: "A2", refresh_token: "R2")
      expect(tokens.expires_at).to be_within(5).of(Time.now + 3_600)
    end

    it "keeps the presented refresh token when the answer omits one" do
      stub_request(:post, token_url)
        .to_return(body: JSON.generate("access_token" => "A2", "expires_in" => 3_600_000))

      expect(described_class.new(http:).refresh(refresh_token: "R1").refresh_token).to eq("R1")
    end

    it "logs out with the refresh token" do
      stub = stub_request(:post, logout_url)
        .with(body: { "client_id" => "Zwift_Mobile_Link", "refresh_token" => "R1" })
        .to_return(status: 204)

      described_class.new(http:).logout(refresh_token: "R1")

      expect(stub).to have_been_requested
    end

    it "reports refused credentials without carrying the password" do
      stub_request(:post, token_url).to_return(status: 401, body: JSON.generate("error" => "invalid_grant"))

      expect { described_class.new(http:).sign_in(email: "a@b.test", password: "secret") }
        .to raise_error(Allure::Zwift::Error::InvalidCredentials) { |error| expect(error.message).not_to include("secret") }
    end

    it "reports a rejected refresh" do
      stub_request(:post, token_url).to_return(status: 400)

      expect { described_class.new(http:).refresh(refresh_token: "R1") }
        .to raise_error(Allure::Zwift::Error::RefreshRejected)
    end

    it "carries the token endpoint's Retry-After" do
      stub_request(:post, token_url).to_return(status: 429, headers: { "Retry-After" => "30" })

      expect { described_class.new(http:).sign_in(email: "a@b.test", password: "x") }
        .to raise_error(Allure::Zwift::Error::RateLimited) { |error| expect(error.retry_after).to eq(30) }
    end

    it "refuses an answer without an access token" do
      stub_request(:post, token_url).to_return(body: "<html>")

      expect { described_class.new(http:).sign_in(email: "a@b.test", password: "x") }
        .to raise_error(Allure::Zwift::Error::Unavailable)
    end
  end

  describe Allure::Zwift::Client do
    subject(:client) do
      described_class.new(refresh_token: "R1", access_token: "A1", expires_at: Time.now + 3600,
                          player_id: "12345", http:)
    end

    it "reads the profile and resolves the player id" do
      stub = stub_request(:get, "#{api_base}/api/profiles/me")
        .with(headers: { "Authorization" => "Bearer A1", "Accept" => "application/json" })
        .to_return(body: JSON.generate("id" => 12_345, "ftp" => 250))

      expect(client.profile["id"]).to eq(12_345)
      expect(stub).to have_been_requested.once
    end

    it "refuses a profile id that is not numeric" do
      stub_request(:get, "#{api_base}/api/profiles/me")
        .to_return(body: JSON.generate("id" => "../evil"))

      anonymous = described_class.new(refresh_token: "R1", access_token: "A1", expires_at: Time.now + 3600, http:)

      expect { anonymous.player_id }.to raise_error(Allure::Zwift::Error::Unavailable)
    end

    it "reads a bare activity list and maps the fields" do
      stub_request(:get, "#{api_base}/api/profiles/12345/activities")
        .with(query: { "start" => "0", "limit" => "30" })
        .to_return(body: JSON.generate([ activity_row(id: 1, started_at: "2026-11-04T18:00:00Z") ]))

      activity = client.activities(start: 0, limit: 30).first

      expect(activity).to have_attributes(
        id: "1", started_at: Time.utc(2026, 11, 4, 18), name: "Watopia ride", sport: "CYCLING",
        world_id: 1, distance_m: 20_000.0, duration_s: 2_700.0,
        fit_bucket: "s3-fit-prd-zwift", fit_key: "fit/1.fit"
      )
      expect(activity.virtual_sport_slug).to eq("cycling_virtual")
    end

    it "accepts the envelope shape the endpoint has returned" do
      stub_request(:get, "#{api_base}/api/profiles/12345/activities")
        .with(query: { "start" => "0", "limit" => "30" })
        .to_return(body: JSON.generate("activities" => [ activity_row(id: 2, started_at: "2026-11-04T18:00:00Z") ]))

      expect(client.activities.map(&:id)).to eq([ "2" ])
    end

    it "reads one activity's detail and refuses an id that could change the path" do
      stub = stub_request(:get, "#{api_base}/api/activities/987")
        .to_return(body: JSON.generate("id" => 987, "profileFtp" => 250))

      expect(client.activity(987)["profileFtp"]).to eq(250)
      expect(stub).to have_been_requested.once
      expect { client.activity("../me") }.to raise_error(ArgumentError)
    end

    it "reads an activity's photos and keeps only Zwift's own S3 objects" do
      stub_request(:get, "#{api_base}/api/activities/987")
        .to_return(body: JSON.generate("snapshotList" => [
          "https://s3-fit-prd-uswest2-zwift.s3.amazonaws.com/prod/img/abc-987",
          "https://evil.example/prod/img/abc-987",
          "https://s3-fit-prd-uswest2-zwift.s3.amazonaws.com/prod/img/../secret"
        ]))

      expect(client.activity_photo_urls(987)).to eq([
        "https://s3-fit-prd-uswest2-zwift.s3.amazonaws.com/prod/img/abc-987"
      ])
    end

    it "downloads a photo from the activity's S3 bucket and refuses any other host" do
      stub = stub_request(:get, "https://s3-fit-prd-uswest2-zwift.s3.amazonaws.com/prod/img/abc-987")
        .to_return(body: "\xFF\xD8\xFF\xE0".b)

      io = StringIO.new
      client.download_photo("https://s3-fit-prd-uswest2-zwift.s3.amazonaws.com/prod/img/abc-987", io:)

      expect(io.string.bytesize).to eq(4)
      expect(stub).to have_been_requested.once
      expect do
        client.download_photo("https://evil.example/prod/img/abc-987", io: StringIO.new)
      end.to raise_error(Allure::Zwift::Error::NotFound)
    end

    it "reads a zone-less startDate as UTC and durationInSeconds before the minutes field" do
      stub_request(:get, "#{api_base}/api/profiles/12345/activities")
        .with(query: { "start" => "0", "limit" => "30" })
        .to_return(body: JSON.generate([ activity_row(id: 1, started_at: "2026-11-04T18:00:00",
                                                     "durationInSeconds" => 1_800) ]))

      activity = client.activities.first

      expect(activity.started_at).to eq(Time.utc(2026, 11, 4, 18))
      expect(activity.duration_s).to eq(1_800.0)
    end

    it "pages until the range is passed and stops at a short page" do
      first_page = Array.new(30) do |index|
        activity_row(id: index + 1, started_at: (Time.utc(2026, 11, 4, 18) - (index * 3600)).iso8601)
      end
      second_page = [
        activity_row(id: 31, started_at: "2026-11-01T10:00:00Z"),
        activity_row(id: 32, started_at: "2026-10-20T10:00:00Z")
      ]
      stub_request(:get, "#{api_base}/api/profiles/12345/activities")
        .with(query: { "start" => "0", "limit" => "30" }).to_return(body: JSON.generate(first_page))
      stub_request(:get, "#{api_base}/api/profiles/12345/activities")
        .with(query: { "start" => "30", "limit" => "30" }).to_return(body: JSON.generate(second_page))
      third = stub_request(:get, "#{api_base}/api/profiles/12345/activities")
        .with(query: { "start" => "60", "limit" => "30" })

      rows = client.list(from: Date.new(2026, 10, 25), to: Date.new(2026, 11, 5))

      expect(rows.map(&:id)).to eq((1..31).map(&:to_s))
      expect(third).not_to have_been_requested
    end

    it "refreshes once on 401 and hands the rotated token over" do
      stub_request(:get, "#{api_base}/api/profiles/me")
        .to_return({ status: 401 }, { body: JSON.generate("id" => 1) })
      stub_request(:post, token_url)
        .to_return(body: token_body("access_token" => "A2", "refresh_token" => "R2", "expires_in" => 3_600_000))
      rotated = []
      client = described_class.new(refresh_token: "R1", access_token: "A1", expires_at: Time.now + 3600,
                                   http:, on_tokens: rotated.method(:<<))

      expect(client.profile["id"]).to eq(1)
      expect(rotated.map(&:refresh_token)).to eq([ "R2" ])
      expect(client.refresh_token).to eq("R2")
    end

    it "says signed out when the token is refused after a refresh" do
      stub_request(:get, "#{api_base}/api/profiles/me").to_return(status: 401)
      stub_request(:post, token_url).to_return(body: token_body)

      expect { client.profile }.to raise_error(Allure::Zwift::Error::SignedOut)
    end

    it "carries Retry-After from the API" do
      stub_request(:get, "#{api_base}/api/profiles/me")
        .to_return(status: 429, headers: { "Retry-After" => "42" })

      expect { client.profile }.to raise_error(Allure::Zwift::Error::RateLimited) do |error|
        expect(error.retry_after).to eq(42)
      end
    end

    it "downloads the FIT without an Authorization header and checks its signature" do
      fit = "\x0E\x10\x00\x00\x00\x00\x00\x00.FIT".b + ("\x00".b * 20)
      stub = stub_request(:get, "https://s3-fit-prd-zwift.s3.amazonaws.com/fit/1.fit")
        .with { |request| request.headers["Authorization"].nil? }
        .to_return(body: fit)
      io = StringIO.new(+"", "w+b")

      client.download_fit_object(bucket: "s3-fit-prd-zwift", key: "fit/1.fit", io:)

      expect(stub).to have_been_requested
      expect(io.string.bytesize).to eq(fit.bytesize)
    end

    it "refuses an activity without a FIT file" do
      expect { client.download_fit_object(bucket: nil, key: nil, io: StringIO.new(+"", "w+b")) }
        .to raise_error(Allure::Zwift::Error::NotFound)
    end

    it "refuses a body that is not a FIT file" do
      stub_request(:get, "https://s3-fit-prd-zwift.s3.amazonaws.com/fit/1.fit").to_return(body: "<html>")

      expect { client.download_fit_object(bucket: "s3-fit-prd-zwift", key: "fit/1.fit", io: StringIO.new(+"", "w+b")) }
        .to raise_error(Allure::Zwift::Error::Unavailable)
    end

    it "refuses a bucket or a key that could leave the S3 host" do
      io = StringIO.new(+"", "w+b")

      expect { client.download_fit_object(bucket: "evil.test/x", key: "a.fit", io:) }.to raise_error(ArgumentError)
      expect { client.download_fit_object(bucket: "s3-fit-prd-zwift", key: "../a.fit", io:) }.to raise_error(ArgumentError)
    end

    it "retries with the mobile agent when Zwift refuses the neutral one" do
      stub_request(:get, "#{api_base}/api/profiles/me")
        .with(headers: { "User-Agent" => Allure::Zwift::Http::USER_AGENT }).to_return(status: 403)
      stub_request(:get, "#{api_base}/api/profiles/me")
        .with(headers: { "User-Agent" => Allure::Zwift::Http::MOBILE_USER_AGENT })
        .to_return(body: JSON.generate("id" => 1))

      expect(client.profile["id"]).to eq(1)
      expect(http.user_agent).to eq(Allure::Zwift::Http::MOBILE_USER_AGENT)
      expect(http.user_agent_fallback_status).to eq(403)
    end

    it "never follows a redirect" do
      stub_request(:get, "#{api_base}/api/profiles/me")
        .to_return(status: 302, headers: { "Location" => "https://evil.test/" })

      expect { client.profile }.to raise_error(Allure::Zwift::Error::Unavailable)
    end
  end

  describe Allure::Zwift::Http do
    it "refuses a host that is not Zwift's" do
      expect { http.get("https://evil.test/api/profiles/me") }.to raise_error(ArgumentError)
      expect { http.post_form("https://evil.test/token", form: {}) }.to raise_error(ArgumentError)
    end
  end

  describe Allure::Zwift::Client::Activity do
    it "declares the virtual sport the listing names" do
      expect(described_class.new(id: "1", sport: "CYCLING").virtual_sport_slug).to eq("cycling_virtual")
      expect(described_class.new(id: "1", sport: "RUNNING").virtual_sport_slug).to eq("running_virtual")
      expect(described_class.new(id: "1", sport: "ROWING").virtual_sport_slug).to be_nil
    end
  end
end
