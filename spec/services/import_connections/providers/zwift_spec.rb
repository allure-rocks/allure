# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportConnections::Providers::Zwift do
  subject(:provider) { described_class.new(connection) }

  let(:api_base) { "https://us-or-rly101.zwift.com" }
  let(:token_url) { "https://secure.zwift.com/auth/realms/zwift/protocol/openid-connect/token" }
  let(:logout_url) { "https://secure.zwift.com/auth/realms/zwift/tokens/logout" }
  let(:connection) do
    create(:import_connection, :linked, provider: "zwift", external_account_id: "8701091",
                                        external_account_name: "rider@example.test",
                                        token_expires_at: 8.days.from_now,
                                        credentials: { "refresh_token" => "R1", "player_id" => "8701091" })
  end
  let(:fit) { "\x0E\x10\x00\x00\x00\x00\x00\x00.FIT".b + ("\x00".b * 20) }
  let(:row) do
    {
      "id" => "2264205323067785264", "startDate" => "2026-11-04T20:08:45Z",
      "name" => "Zwift - Two Bridges Loop in Watopia", "sport" => "CYCLING", "worldId" => 1,
      "distanceInMeters" => 7169, "duration" => 14,
      "fitFileBucket" => "s3-fit-prd-uswest2-zwift", "fitFileKey" => "prod/8701091/d77c88cc"
    }
  end
  let(:listed_activity) do
    remote_activity("2264205323067785264", name: "Zwift - Two Bridges Loop in Watopia",
                    started_at: Time.utc(2026, 11, 4, 20, 8, 45),
                    sport_hint: "cycling_virtual",
                    provider_metadata: { "fit_bucket" => "s3-fit-prd-uswest2-zwift",
                                         "fit_key" => "prod/8701091/d77c88cc" })
  end

  before do
    stub_const("Allure::Zwift::Http::MIN_INTERVAL", 0)
    stub_request(:post, token_url).to_return(body: JSON.generate(
      "access_token" => "A1", "refresh_token" => "R2", "expires_in" => 3_600, "refresh_expires_in" => 691_200
    ))
    stub_request(:post, logout_url).to_return(status: 204)
    stub_request(:get, "#{api_base}/api/profiles/me")
      .with(headers: { "Authorization" => "Bearer A1" })
      .to_return(body: JSON.generate("id" => 8_701_091))
    stub_request(:get, "#{api_base}/api/profiles/8701091/activities")
      .with(query: { "start" => "0", "limit" => "30" })
      .to_return(body: JSON.generate([ row ]))
    stub_request(:get, "#{api_base}/api/activities/2264205323067785264")
      .to_return(body: JSON.generate("id" => 2_264_205_323_067_785_264, "snapshotList" => []))
    stub_request(:get, "https://s3-fit-prd-uswest2-zwift.s3.amazonaws.com/prod/8701091/d77c88cc")
      .to_return(body: fit)
  end

  it_behaves_like "an import provider"

  it "lists the window's activities with the virtual sport and the FIT pointer" do
    activities = provider.list(from: Time.utc(2026, 11, 1), to: Time.utc(2026, 11, 5))

    expect(activities.sole).to have_attributes(
      external_id: "2264205323067785264", name: "Zwift - Two Bridges Loop in Watopia",
      started_at: Time.utc(2026, 11, 4, 20, 8, 45), sport_hint: "cycling_virtual",
      geometry: true, manual: false,
      provider_metadata: { "fit_bucket" => "s3-fit-prd-uswest2-zwift", "fit_key" => "prod/8701091/d77c88cc" }
    )
  end

  it "round trips the FIT pointer through an entry's metadata" do
    activity = provider.list(from: Time.utc(2026, 11, 1), to: Time.utc(2026, 11, 5)).sole

    rebuilt = Allure::RemoteImports::RemoteActivity.from_metadata(activity.external_id, activity.metadata)

    expect(rebuilt.provider_metadata).to eq(activity.provider_metadata)
  end

  describe "an activity Zwift has not finished writing" do
    include ActiveSupport::Testing::TimeHelpers

    def stub_listing(*rows)
      stub_request(:get, "#{api_base}/api/profiles/8701091/activities")
        .with(query: { "start" => "0", "limit" => "30" })
        .to_return(body: JSON.generate(rows))
    end

    def listed
      provider.list(from: Time.utc(2026, 11, 1), to: Time.utc(2026, 11, 5))
    end

    it "lists an activity once its declared end has settled, and carries that end" do
      travel_to Time.utc(2026, 11, 4, 21, 0) do
        expect(listed.sole.ended_at).to eq(Time.utc(2026, 11, 4, 20, 22, 45))
      end
    end

    it "leaves out the activity the athlete is still riding" do
      # Started at 20:08:45, declared to last 14 minutes: at 20:15 it is still
      # running, and its FIT is a snapshot with a provisional name.
      travel_to Time.utc(2026, 11, 4, 20, 15) do
        expect(listed).to be_empty
      end
    end

    it "leaves out an activity whose declared end is still in the future" do
      stub_listing(row.merge("duration" => 120))

      travel_to Time.utc(2026, 11, 4, 21, 0) do
        expect(listed).to be_empty
      end
    end

    it "leaves out an activity that just started without a declared duration" do
      stub_listing(row.except("duration", "durationInSeconds"))

      travel_to Time.utc(2026, 11, 4, 20, 10) do
        expect(listed).to be_empty
      end
    end

    it "lists an activity with no declared duration once it started long ago" do
      stub_listing(row.except("duration", "durationInSeconds"))

      travel_to Time.utc(2026, 11, 4, 21, 0) do
        expect(listed.sole.ended_at).to be_nil
      end
    end
  end

  it "fetches the FIT with the declared virtual sport" do
    fetched = provider.fetch(listed_activity)

    expect(fetched).to have_attributes(filename: "zwift-2264205323067785264.fit",
                                       declared_sport: "cycling_virtual",
                                       title: "Zwift - Two Bridges Loop in Watopia")
    expect(fetched.io.read.bytesize).to eq(fit.bytesize)
  ensure
    fetched&.io&.close
  end

  it "persists the refresh token the refresh rotates" do
    provider.verify!

    expect(connection.reload.credential(:refresh_token)).to eq("R2")
    expect(connection.token_expires_at).to be_within(1.minute).of(8.days.from_now)
  end

  it "turns a rejected refresh into an authentication error" do
    stub_request(:post, token_url).to_return(status: 400)

    expect { provider.verify! }.to raise_error(Allure::RemoteImports::Error::AuthError)
  end

  it "skips an activity without a FIT pointer" do
    activity = remote_activity("1", provider_metadata: {})

    expect { provider.fetch(activity) }.to raise_error(Allure::RemoteImports::Error::NotFound)
  end

  it "has no equipment" do
    expect(provider.equipment).to eq([])
  end

  it "downloads the activity's photos and counts the one it could not fetch" do
    photo_url = "https://s3-fit-prd-uswest2-zwift.s3.amazonaws.com/prod/img/abc-1"
    missing_url = "https://s3-fit-prd-uswest2-zwift.s3.amazonaws.com/prod/img/abc-2"
    stub_request(:get, "#{api_base}/api/activities/2264205323067785264")
      .to_return(body: JSON.generate("snapshotList" => [ photo_url, missing_url ]))
    stub_request(:get, photo_url).to_return(body: "\xFF\xD8\xFF\xE0".b)
    stub_request(:get, missing_url).to_return(status: 404)

    set = provider.photos(listed_activity)

    expect(set.listed).to eq(2)
    expect(set.photos.length).to eq(1)
    expect(set.photos.first.filename).to eq("zwift-2264205323067785264-0.jpg")
    expect(set.photos.first.io.read.bytesize).to eq(4)
  ensure
    set&.photos&.each { |photo| photo.io.close! }
  end

  it "offers no photos while the photo feature is off" do
    allow(Allure::Photos::Config).to receive(:enabled?).and_return(false)

    expect(provider.photos(listed_activity)).to eq(Allure::RemoteImports::PhotoSet.new)
  end
end
