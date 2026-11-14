# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::ActorProvisioner do
  let(:user) { create(:user, username: "marie") }

  it "provisions a stable local actor with an RSA key pair" do
    actor = described_class.new(user: user).call!
    private_key = OpenSSL::PKey::RSA.new(actor.private_key_ciphertext)

    expect(actor).to be_local
    expect(actor.user).to eq(user)
    expect(actor.uri).to eq("http://allure.test:3001/users/marie")
    expect(actor.public_key_id).to eq("http://allure.test:3001/users/marie#main-key")
    expect(actor.inbox_url).to eq("http://allure.test:3001/users/marie/inbox")
    expect(private_key.n.num_bits).to be >= 2048
    expect(OpenSSL::PKey::RSA.new(actor.public_key_pem).public?).to be(true)
  end

  it "is idempotent and never rotates the key" do
    first = described_class.new(user: user).call!
    first_key = first.private_key_ciphertext

    second = described_class.new(user: user).call!

    expect(second.id).to eq(first.id)
    expect(second.private_key_ciphertext).to eq(first_key)
  end

  it "returns an existing actor without locking the user row" do
    described_class.new(user: user).call!
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql]
    end

    described_class.new(user: User.find(user.id)).call!

    expect(statements.grep(/FOR UPDATE/i)).to be_empty
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it "rejects an actor whose stored identity conflicts with the config" do
    actor = described_class.new(user: user).call!
    other_config = Allure::Federation::Config.new(base_url: "https://other.example", protocol: "https")

    expect {
      described_class.new(user: user, config: other_config).call!
    }.to raise_error(described_class::IdentityConflict)
    expect(actor.reload.uri).to eq("http://allure.test:3001/users/marie")
  end

  it "does not silently replace an existing actor URI" do
    user = create(:user, username: "marie")
    actor = create(:actor, uri: user.actor_uri)

    expect {
      described_class.new(user: user).call!
    }.to raise_error(described_class::IdentityConflict)
    expect(actor.reload.user_id).to be_nil
  end
end
