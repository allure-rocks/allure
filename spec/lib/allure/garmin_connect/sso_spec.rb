# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::GarminConnect::Sso do
  subject(:sso) { described_class.new(sleeper: ->(seconds) { pauses << seconds }, random: Random.new(1)) }

  let(:pauses) { [] }
  let(:mobile_login) { %r{\Ahttps://sso\.garmin\.com/mobile/api/login\?} }
  let(:portal_page) { %r{\Ahttps://sso\.garmin\.com/portal/sso/en-US/sign-in\?} }
  let(:portal_login) { %r{\Ahttps://sso\.garmin\.com/portal/api/login\?} }

  def json_body(type, extra = {})
    { status: 200, body: { responseStatus: { type: } }.merge(extra).to_json, headers: { "Content-Type" => "application/json" } }
  end

  it "signs in through the mobile flow with the iOS client" do
    stub = stub_request(:post, mobile_login)
      .with(query: hash_including("clientId" => "GCM_IOS_DARK", "service" => "https://mobile.integration.garmin.com/gcm/ios"),
            body: { username: "rider@example.test", password: "secret", rememberMe: true, captchaToken: "" }.to_json)
      .to_return(json_body("SUCCESSFUL", serviceTicketId: "ST-1"))

    result = sso.sign_in(email: " rider@example.test ", password: "secret")

    expect(stub).to have_been_requested
    expect(result).to eq(described_class::SignedIn.new(ticket: "ST-1", service_url: "https://mobile.integration.garmin.com/gcm/ios", strategy: :mobile))
    expect(pauses).to be_empty
  end

  it "falls through to the portal after a bot challenge, pausing between its GET and POST" do
    stub_request(:post, mobile_login).to_return(status: 403, body: "<html>challenge</html>")
    stub_request(:get, portal_page).to_return(status: 200, body: "<html/>", headers: { "Set-Cookie" => "SESSION=abc; Path=/; Secure" })
    login = stub_request(:post, portal_login)
      .with(headers: { "Cookie" => "SESSION=abc" }, query: hash_including("clientId" => "GarminConnect"))
      .to_return(json_body("SUCCESSFUL", serviceTicketId: "ST-2"))

    result = sso.sign_in(email: "rider@example.test", password: "secret")

    expect(login).to have_been_requested
    expect(result.service_url).to eq("https://connect.garmin.com/app")
    expect(pauses.sole).to be_between(10.0, 20.0)
    expect(sso.attempts.map(&:strategy)).to eq(%i[mobile portal])
  end

  it "stops at once on invalid credentials" do
    stub_request(:post, mobile_login).to_return(json_body("INVALID_USERNAME_PASSWORD"))

    expect { sso.sign_in(email: "a@b.test", password: "wrong") }.to raise_error(Allure::GarminConnect::Error::InvalidCredentials)
    expect(a_request(:get, portal_page)).not_to have_been_made
  end

  it "stops at a 429 instead of trying the portal" do
    stub_request(:post, mobile_login).to_return(status: 429, body: "")

    expect { sso.sign_in(email: "a@b.test", password: "x") }.to raise_error(Allure::GarminConnect::Error::RateLimited)
    expect(a_request(:get, portal_page)).not_to have_been_made
  end

  it "raises the last refusal when both strategies meet a captcha" do
    stub_request(:post, mobile_login).to_return(json_body("CAPTCHA_REQUIRED"))
    stub_request(:get, portal_page).to_return(status: 200, body: "")
    stub_request(:post, portal_login).to_return(status: 429, body: "")

    expect { sso.sign_in(email: "a@b.test", password: "x") }.to raise_error(Allure::GarminConnect::Error::RateLimited)
    expect(sso.attempts.map(&:outcome)).to eq([ "mobile: CAPTCHA required (bot challenge)", "portal: HTTP 429" ])
  end

  it "returns a storable MFA state and completes it on the stored cookies" do
    stub_request(:post, mobile_login)
      .to_return(json_body("MFA_REQUIRED", customerMfaInfo: { mfaLastMethodUsed: "email" })
                   .merge(headers: { "Content-Type" => "application/json", "Set-Cookie" => "CASTGC=tgc; Secure" }))

    challenge = sso.sign_in(email: "a@b.test", password: "x")
    expect(challenge).to be_a(described_class::MfaRequired)
    expect(challenge.to_h).to include(flow: "mobile", method: "email", cookies: { "CASTGC" => "tgc" })

    stub_request(:post, %r{/mobile/api/mfa/verifyCode})
      .with(headers: { "Cookie" => "CASTGC=tgc" }, body: hash_including("mfaVerificationCode" => "123456"))
      .to_return(json_body("SUCCESSFUL", serviceTicketId: "ST-3"))

    result = described_class.new.verify_mfa(state: JSON.parse(challenge.to_h.to_json), code: " 123456 ")

    expect(result.ticket).to eq("ST-3")
    expect(result.service_url).to eq("https://mobile.integration.garmin.com/gcm/ios")
  end

  it "tries the other MFA endpoint and reports a wrong code" do
    state = { flow: "mobile", method: "email", service_url: "https://mobile.integration.garmin.com/gcm/ios", cookies: {} }
    stub_request(:post, %r{/mobile/api/mfa/verifyCode}).to_return(json_body("INVALID_MFA_CODE"))
    portal = stub_request(:post, %r{/portal/api/mfa/verifyCode}).to_return(json_body("INVALID_MFA_CODE"))

    expect { sso.verify_mfa(state:, code: "000000") }.to raise_error(Allure::GarminConnect::Error::MfaFailed)
    expect(portal).to have_been_requested
  end

  it "uses the garmin.cn hosts for a China account" do
    cn = described_class.new(region: Allure::GarminConnect::Region.new("cn"))
    stub_request(:post, %r{\Ahttps://sso\.garmin\.cn/mobile/api/login})
      .with(query: hash_including("service" => "https://mobile.integration.garmin.cn/gcm/ios"))
      .to_return(json_body("SUCCESSFUL", serviceTicketId: "ST-CN"))

    expect(cn.sign_in(email: "a@b.test", password: "x").ticket).to eq("ST-CN")
  end
end
