# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::Passkeys do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Allure::Federation.config.base_url) }

  def register(nickname: "Phone")
    options = described_class.registration_options(user)
    raw = client.create(challenge: options.challenge, rp_id: Allure::Federation.config.host)
    described_class.register(user, raw.to_json, challenge: options.challenge, nickname:)
  end

  it "registers a credential for this instance's origin and host" do
    credential = register

    expect(credential).to be_persisted
    expect(credential.nickname).to eq("Phone")
    expect(user.reload.webauthn_id).to be_present
  end

  it "offers creation options that exclude the account's credentials and prefer discoverable keys" do
    register
    options = described_class.registration_options(user).as_json.deep_stringify_keys

    expect(options["excludeCredentials"].map { |entry| entry["id"] }).to eq(user.webauthn_credentials.pluck(:external_id))
    expect(options.dig("authenticatorSelection", "residentKey")).to eq("preferred")
    expect(options.dig("user", "name")).to eq(user.handle)
  end

  it "refuses a credential created for another origin" do
    options = described_class.registration_options(user)
    raw = WebAuthn::FakeClient.new("https://evil.example").create(challenge: options.challenge, rp_id: "evil.example")

    expect(described_class.register(user, raw.to_json, challenge: options.challenge, nickname: "Evil")).to be_nil
  end

  it "refuses an answer to another challenge" do
    options = described_class.registration_options(user)
    raw = client.create(challenge: WebAuthn::Credential.options_for_create(user: { id: "x", name: "x" }).challenge,
                        rp_id: Allure::Federation.config.host)

    expect(described_class.register(user, raw.to_json, challenge: options.challenge, nickname: "Phone")).to be_nil
  end

  it "authenticates with a registered credential and records its use" do
    credential = register
    options = described_class.authentication_options(user)
    raw = client.get(challenge: options.challenge, rp_id: Allure::Federation.config.host, sign_count: 5)

    expect(described_class.authenticate(user, raw.to_json, challenge: options.challenge)).to eq(credential)
    expect(credential.reload).to have_attributes(sign_count: 5, last_used_at: be_present)
  end

  it "refuses another account's credential" do
    register
    other = create(:user)
    options = described_class.authentication_options(other)
    raw = client.get(challenge: options.challenge, rp_id: Allure::Federation.config.host)

    expect(described_class.authenticate(other, raw.to_json, challenge: options.challenge)).to be_nil
  end

  it "refuses malformed input" do
    expect(described_class.authenticate(user, "not json", challenge: "abc")).to be_nil
    expect(described_class.register(user, "[1]", challenge: "abc", nickname: "x")).to be_nil
  end
end
