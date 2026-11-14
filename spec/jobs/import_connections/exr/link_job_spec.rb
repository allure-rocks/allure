# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportConnections::Exr::LinkJob do
  let(:user) { create(:user) }
  let(:connection) { ImportConnection.for(user, "exr") }
  let(:session) { instance_double(Allure::Exr::Session) }
  let(:cookie) { Allure::Exr::Http::Cookie.new(name: "remember_web_abc", value: "R1", expires_at: Time.utc(2031, 10, 8)) }

  around { |example| with_remote_import_enabled("exr") { example.run } }

  before do
    allow(described_class).to receive(:perform_later)
    ImportConnections::Linking.new(connection).start!(email: "rower@example.test", password: "secret-pass")
    stub_request(:get, "https://account.exrgame.com/sessions")
      .to_return(body: Rails.root.join("spec/fixtures/exr/sessions_page.html").read)
  end

  def run = described_class.perform_now(connection.reload, session:)

  it "keeps the password out of the job arguments" do
    expect(described_class).to have_received(:perform_later).with(connection)
  end

  it "links and keeps only the remember cookie" do
    allow(session).to receive(:sign_in).with(email: "rower@example.test", password: "secret-pass").and_return(cookie)

    run

    expect(connection.reload).to have_attributes(status: "linked", external_account_name: "rower@example.test",
                                                 token_expires_at: Time.utc(2031, 10, 8))
    expect(connection.credentials).to eq("remember_cookie_name" => "remember_web_abc", "remember_cookie" => "R1")
  end

  {
    Allure::Exr::Error::InvalidCredentials => "invalid_credentials",
    Allure::Exr::Error::NoRememberCookie => "no_remember",
    Allure::Exr::Error::Unavailable => "unavailable"
  }.each do |error, reason|
    it "returns to the previous state with the reason on #{reason}" do
      allow(session).to receive(:sign_in).and_raise(error, "no")

      run

      expect(connection.reload).to have_attributes(
        status: "unlinked", credentials: {},
        last_sync_error: I18n.t("settings.connections.exr.errors.#{reason}", locale: user.locale)
      )
    end
  end

  it "expires a link whose cookie does not open the list" do
    allow(session).to receive(:sign_in).and_return(cookie)
    stub_request(:get, "https://account.exrgame.com/sessions")
      .to_return(status: 302, headers: { "Location" => "https://account.exrgame.com/login" })

    run

    expect(connection.reload.status).to eq("expired")
  end
end
