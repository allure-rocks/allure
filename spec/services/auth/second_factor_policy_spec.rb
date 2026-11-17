# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::SecondFactorPolicy do
  let(:now) { Time.zone.parse("2026-10-09 12:00") }

  around do |example|
    previous = ENV.to_h.slice("INSTANCE_OPERATOR_USERNAME", "AUTH_2FA_GRACE_DAYS", "DEMO_INSTANCE")
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    ENV.delete("AUTH_2FA_GRACE_DAYS")
    example.run
  ensure
    %w[INSTANCE_OPERATOR_USERNAME AUTH_2FA_GRACE_DAYS DEMO_INSTANCE].each { |key| ENV[key] = previous[key] }
  end

  it "starts the obligation when a password account is created" do
    user = create(:user)

    expect(user.second_factor_required_since).to be_within(5.seconds).of(Time.current)
  end

  it "gives a password account fourteen days" do
    user = create(:user, second_factor_required_since: now - 13.days)
    policy = described_class.new(user, now:)

    expect(policy.state).to eq(:grace)
    expect(policy.deadline).to eq(now + 1.day)
    expect(policy.days_left).to eq(1)
  end

  it "requires enrolment once the grace period has ended" do
    user = create(:user, second_factor_required_since: now - 14.days)

    expect(described_class.new(user, now:)).to be_required
  end

  it "reads the grace period from the environment, zero included" do
    ENV["AUTH_2FA_GRACE_DAYS"] = "0"
    user = create(:user, second_factor_required_since: now - 1.minute)

    expect(described_class.new(user, now:)).to be_required
  end

  it "gives the operator no grace period" do
    operator = create(:user, username: "operator", second_factor_required_since: now - 1.minute)

    expect(described_class.new(operator, now:)).to be_required
  end

  it "is satisfied by an authenticator app or a passkey" do
    totp = create(:user, :with_totp, second_factor_required_since: now - 30.days)
    passkey = create(:user, second_factor_required_since: now - 30.days)
    passkey.webauthn_credentials.create!(external_id: "abc", public_key: "key", nickname: "Phone")

    expect(described_class.new(totp, now:)).to be_satisfied
    expect(described_class.new(passkey, now:)).to be_satisfied
  end

  it "owes nothing when no obligation started" do
    user = create(:user)
    user.update_column(:second_factor_required_since, nil)

    expect(described_class.new(user, now:)).to be_satisfied
  end

  it "counts accounts per state with the same rules" do
    create(:user, :with_totp, second_factor_required_since: now - 30.days)
    create(:user, second_factor_required_since: now - 1.day)
    create(:user, second_factor_required_since: now - 20.days)
    create(:user, username: "operator", second_factor_required_since: now - 1.minute)

    expect(described_class.counts(now:)).to eq("satisfied" => 1, "grace" => 1, "required" => 2)
  end

  it "owes nothing on a demo instance, the operator included (docs/dev/DEMO.md)" do
    ENV["DEMO_INSTANCE"] = "true"
    overdue = create(:user, second_factor_required_since: now - 30.days)
    operator = create(:user, username: "operator", second_factor_required_since: now - 1.minute)

    expect(described_class.new(overdue, now:)).to be_satisfied
    expect(described_class.new(operator, now:)).to be_satisfied
    expect(described_class.counts(now:)).to eq("satisfied" => User.count, "grace" => 0, "required" => 0)
  end
end
