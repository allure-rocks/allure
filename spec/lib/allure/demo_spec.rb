# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Demo do
  around do |example|
    previous = ENV.to_h.slice("DEMO_INSTANCE", "DEMO_ACCOUNTS", "DEMO_PASSWORD", "DEMO_OPERATOR_PASSWORD",
                              "INSTANCE_OPERATOR_USERNAME", "DEMO_RESET_AT", "TZ")
    ENV.delete("DEMO_INSTANCE")
    ENV.delete("DEMO_ACCOUNTS")
    ENV.delete("DEMO_PASSWORD")
    ENV.delete("DEMO_OPERATOR_PASSWORD")
    ENV.delete("INSTANCE_OPERATOR_USERNAME")
    ENV.delete("DEMO_RESET_AT")
    ENV.delete("TZ")
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  it "is off by default and reads its switch from the environment" do
    expect(described_class).not_to be_enabled
    expect(described_class.accounts).to be_empty

    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = " tom , marie "

    expect(described_class).to be_enabled
    expect(described_class.accounts).to eq(%w[tom marie])
  end

  it "recognises exactly the shared accounts, and only in demo mode" do
    tom = build_stubbed(:user, username: "tom")
    other = build_stubbed(:user, username: "other")

    ENV["DEMO_ACCOUNTS"] = "tom,marie"
    expect(described_class.shared_account?(tom)).to be(false)

    ENV["DEMO_INSTANCE"] = "true"
    expect(described_class.shared_account?(tom)).to be(true)
    expect(described_class.shared_account?(other)).to be(false)
    expect(described_class.shared_account?(nil)).to be(false)
  end

  it "refuses to publish the operator, including differently cased configuration" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = "tom, MARIE "
    ENV["INSTANCE_OPERATOR_USERNAME"] = " Marie "

    expect { described_class.accounts }
      .to raise_error(Allure::Demo::InvalidConfiguration, /DEMO_ACCOUNTS must not include INSTANCE_OPERATOR_USERNAME/)
  end

  it "does not apply the operator check outside demo mode" do
    ENV["DEMO_ACCOUNTS"] = "tom,marie"
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"

    expect(described_class.accounts).to eq(%w[tom marie])
  end

  it "requires a stable operator password when the console is configured" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"

    expect { described_class.validate! }
      .to raise_error(Allure::Demo::InvalidConfiguration, /DEMO_OPERATOR_PASSWORD is required/)
  end

  it "refuses an operator password shorter than the account minimum" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"
    ENV["DEMO_OPERATOR_PASSWORD"] = "too-short"

    expect { described_class.validate! }
      .to raise_error(Allure::Demo::InvalidConfiguration, /at least #{User::MINIMUM_PASSWORD_LENGTH}/)
  end

  it "refuses the shared password as the operator's" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"
    ENV["DEMO_PASSWORD"] = "AllureRocks2026"
    ENV["DEMO_OPERATOR_PASSWORD"] = "AllureRocks2026"

    expect { described_class.validate! }
      .to raise_error(Allure::Demo::InvalidConfiguration, /must differ from DEMO_PASSWORD/)
  end

  it "accepts a configured operator password" do
    ENV["DEMO_INSTANCE"] = "true"
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"
    ENV["DEMO_OPERATOR_PASSWORD"] = "operator-password-2026"

    expect { described_class.validate! }.not_to raise_error
  end

  it "does not require an operator password outside demo mode" do
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"

    expect { described_class.validate! }.not_to raise_error
  end

  it "resolves the nightly reset to its next occurrence, in the configured zone" do
    ENV["TZ"] = "Europe/Paris"
    ENV["DEMO_RESET_AT"] = "03:00"
    paris = Time.find_zone("Europe/Paris")

    # Mid-summer: Paris is UTC+2, nowhere near a transition.
    morning = Time.zone.parse("2026-07-31 14:00:00")
    expect(described_class.reset_at(morning)).to eq(paris.parse("2026-08-01 03:00"))

    # Five minutes before (Paris 02:56): the warning window must still point at
    # today's reset, not tomorrow's.
    just_before = Time.zone.parse("2026-07-31 00:56:00")
    expect(described_class.reset_at(just_before)).to eq(paris.parse("2026-07-31 03:00"))

    after = Time.zone.parse("2026-07-31 02:30:00")
    expect(described_class.reset_at(after)).to eq(paris.parse("2026-08-01 03:00"))
  end

  it "defaults the reset to 03:00 in the application zone" do
    expect(described_class.reset_at(Time.zone.parse("2026-10-31 14:00:00")).hour).to eq(3)
  end
end
