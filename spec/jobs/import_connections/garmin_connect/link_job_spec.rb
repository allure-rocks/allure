# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportConnections::GarminConnect::LinkJob do
  let(:user) { create(:user) }
  let(:connection) { ImportConnection.for(user, "garmin_connect") }
  let(:sso) { instance_double(Allure::GarminConnect::Sso) }
  let(:di_token) { instance_double(Allure::GarminConnect::DiToken) }
  # A token still valid whenever the suite runs.
  let(:token_expires_at) { 1.day.from_now.utc.change(usec: 0) }
  let(:token) do
    Allure::GarminConnect::DiToken::Token.new(access_token: "a1", refresh_token: "r1", client_id: "CID",
                                              expires_at: token_expires_at)
  end
  let(:signed_in) { Allure::GarminConnect::Sso::SignedIn.new(ticket: "ST-1", service_url: "https://svc", strategy: :mobile) }
  let(:challenge) do
    Allure::GarminConnect::Sso::MfaRequired.new(flow: "mobile", method: "email", service_url: "https://svc",
                                                cookies: { "CASTGC" => "tgc" })
  end

  around { |example| with_remote_import_enabled { example.run } }

  before do
    allow(described_class).to receive(:perform_later)
    ImportConnections::Linking.new(connection).start!(email: "rider@example.test", password: "secret", region: "com")
    stub_request(:get, "https://connectapi.garmin.com/userprofile-service/socialProfile")
      .to_return(status: 200, body: { profileId: 42, fullName: "Rider Garmin", displayName: "uuid" }.to_json)
  end

  def run = described_class.perform_now(connection.reload, sso:, di_token:)

  it "keeps the password out of the job arguments" do
    expect(described_class).to have_received(:perform_later).with(connection)
    expect(connection.reload).to have_attributes(status: "pending", pending_expires_at: be_present)
  end

  it "links, names the account and keeps only the tokens" do
    allow(sso).to receive(:sign_in).with(email: "rider@example.test", password: "secret").and_return(signed_in)
    allow(di_token).to receive(:exchange).with(ticket: "ST-1", service_url: "https://svc").and_return(token)
    Notification.create!(user:, kind: "import_connection_expired", subject: connection)

    run

    expect(connection.reload).to have_attributes(status: "linked", external_account_id: "42",
                                                 external_account_name: "Rider Garmin",
                                                 token_expires_at: token_expires_at)
    expect(connection.credentials.keys).to contain_exactly("di_token", "di_refresh_token", "di_client_id")
    expect(Notification.where(subject: connection)).to be_empty
  end

  it "waits for a verification code, then completes with it" do
    allow(sso).to receive(:sign_in).and_return(challenge)

    run

    expect(connection.reload).to have_attributes(status: "mfa_pending")
    expect(connection.credentials.keys).not_to include("pending_password")
    expect(connection.credential(:mfa_state)).to include("cookies" => { "CASTGC" => "tgc" })

    ImportConnections::Linking.new(connection).submit_code!(" 123 456 ")
    allow(sso).to receive(:verify_mfa).with(state: hash_including("flow" => "mobile"), code: "123456").and_return(signed_in)
    allow(di_token).to receive(:exchange).and_return(token)

    run

    expect(connection.reload).to have_attributes(status: "linked")
    expect(connection.credentials.keys).to contain_exactly("di_token", "di_refresh_token", "di_client_id")
  end

  it "keeps the challenge open after a wrong code" do
    allow(sso).to receive(:sign_in).and_return(challenge)
    run
    ImportConnections::Linking.new(connection.reload).submit_code!("000000")
    allow(sso).to receive(:verify_mfa).and_raise(Allure::GarminConnect::Error::MfaFailed, "wrong")

    run

    expect(connection.reload).to have_attributes(status: "mfa_pending",
                                                 last_sync_error: I18n.t("settings.connections.garmin_connect.errors.mfa_failed", locale: user.locale))
    expect(connection.credential(:pending_mfa_code)).to be_nil
  end

  {
    Allure::GarminConnect::Error::InvalidCredentials => "invalid_credentials",
    Allure::GarminConnect::Error::RateLimited => "rate_limited",
    Allure::GarminConnect::Error::Refused => "refused"
  }.each do |error, reason|
    it "returns to the previous state with the reason on #{reason}" do
      allow(sso).to receive(:sign_in).and_raise(error, "no")

      run

      expect(connection.reload).to have_attributes(
        status: "unlinked", pending_expires_at: nil,
        last_sync_error: I18n.t("settings.connections.garmin_connect.errors.#{reason}", locale: user.locale)
      )
      expect(connection.credentials).to eq({})
    end
  end

  it "abandons an attempt past its expiry without signing in" do
    allow(sso).to receive(:sign_in)
    connection.update!(pending_expires_at: 1.minute.ago)

    run

    expect(sso).not_to have_received(:sign_in)
    expect(connection.reload).to have_attributes(status: "unlinked", credentials: {})
  end
end
