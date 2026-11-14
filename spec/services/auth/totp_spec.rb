# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::Totp do
  let(:user) { create(:user, :with_totp) }
  let(:now) { Time.zone.parse("2026-10-09 12:00:10") }

  def code_at(time) = ROTP::TOTP.new(user.otp_secret).at(time)

  it "accepts the current code once and refuses its replay" do
    expect(described_class.verify!(user, code_at(now), now:)).to be(true)
    expect(described_class.verify!(user.reload, code_at(now), now:)).to be(false)
  end

  it "tolerates one step of drift either way, not two" do
    expect(described_class.verify!(user, code_at(now - 30), now:)).to be(true)
    expect(described_class.verify!(user.reload, code_at(now + 30), now:)).to be(true)
    expect(described_class.verify!(user.reload, code_at(now + 60), now:)).to be(false)
  end

  it "refuses a code older than the last accepted one" do
    described_class.verify!(user, code_at(now), now:)

    expect(described_class.verify!(user.reload, code_at(now - 30), now:)).to be(false)
  end

  it "ignores spaces and refuses anything but six digits" do
    expect(described_class.verify!(user, code_at(now).insert(3, " "), now:)).to be(true)
    expect(described_class.code?("abcdef")).to be(false)
    expect(described_class.code?("12345")).to be(false)
  end

  it "refuses an account without an authenticator app" do
    expect(described_class.verify!(create(:user), "123456", now:)).to be(false)
  end

  it "builds a provisioning URI named after the instance and the handle" do
    uri = described_class.provisioning_uri(user, "JBSWY3DPEHPK3PXP")

    expect(uri).to start_with("otpauth://totp/")
    expect(uri).to include("secret=JBSWY3DPEHPK3PXP", "issuer=Allure", user.username)
    expect(described_class.qr_svg(uri)).to include("<svg")
  end
end
