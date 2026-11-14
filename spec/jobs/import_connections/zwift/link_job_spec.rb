# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportConnections::Zwift::LinkJob do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:connection) { ImportConnection.for(user, "zwift") }
  let(:session) { instance_double(Allure::Zwift::Auth) }
  let(:api_base) { "https://us-or-rly101.zwift.com" }
  let(:token_url) { "https://secure.zwift.com/auth/realms/zwift/protocol/openid-connect/token" }
  let(:tokens) do
    Allure::Zwift::Auth::Tokens.new(
      access_token: "A1", refresh_token: "R1", expires_at: 1.hour.from_now,
      refresh_expires_in: 691_200, refresh_expires_at: 8.days.from_now
    )
  end

  around { |example| with_remote_import_enabled("zwift") { example.run } }

  before do
    stub_const("Allure::Zwift::Http::MIN_INTERVAL", 0)
    allow(described_class).to receive(:perform_later)
    ImportConnections::Linking.new(connection).start!(email: "rider@example.test", password: "secret-pass")
    stub_request(:get, "#{api_base}/api/profiles/me")
      .with(headers: { "Authorization" => "Bearer A1" })
      .to_return(body: JSON.generate("id" => 1_234_567))
    stub_request(:post, token_url).to_return(body: JSON.generate(
      "access_token" => "A2", "refresh_token" => "R2", "expires_in" => 3_600, "refresh_expires_in" => 691_200
    ))
    stub_request(:get, "#{api_base}/api/profiles/me")
      .with(headers: { "Authorization" => "Bearer A2" })
      .to_return(body: JSON.generate("id" => 1_234_567))
  end

  def run = described_class.perform_now(connection.reload, session:)

  it "keeps the password out of the job arguments" do
    expect(described_class).to have_received(:perform_later).with(connection)
  end

  it "links and keeps only the refresh token and the athlete id" do
    allow(session).to receive(:sign_in).with(email: "rider@example.test", password: "secret-pass").and_return(tokens)

    run

    expect(connection.reload).to have_attributes(
      status: "linked", external_account_id: "1234567", external_account_name: "rider@example.test"
    )
    expect(connection.credentials).to eq("refresh_token" => "R2", "player_id" => "1234567")
    expect(connection.token_expires_at).to be_within(1.minute).of(8.days.from_now)
  end

  {
    Allure::Zwift::Error::InvalidCredentials => "invalid_credentials",
    Allure::Zwift::Error::RateLimited => "rate_limited",
    Allure::Zwift::Error::Unavailable => "unavailable"
  }.each do |error, reason|
    it "returns to the previous state with the reason on #{reason}" do
      allow(session).to receive(:sign_in).and_raise(error, "no")

      run

      expect(connection.reload).to have_attributes(
        status: "unlinked", credentials: {},
        last_sync_error: I18n.t("settings.connections.zwift.errors.#{reason}", locale: user.locale)
      )
    end
  end

  it "expires a link whose refresh token does not open the profile" do
    allow(session).to receive(:sign_in).and_return(tokens)
    stub_request(:post, token_url).to_return(status: 400)

    run

    expect(connection.reload.status).to eq("expired")
  end

  it "resumes the batches a dead token left queued" do
    allow(session).to receive(:sign_in).and_return(tokens)
    batch = create(:workout_import_batch, user:, source: "zwift", import_connection: connection,
                                          status: "queued", trigger: "scheduled")

    expect { run }.to have_enqueued_job(Workouts::RemoteImportBatchJob).with(batch)
  end
end
