# frozen_string_literal: true

require "rails_helper"

# The demo mode's shared playground accounts (docs/dev/DEMO.md): no visitor may
# lock the next one out, no session IP is ever persisted, and the operator
# reaches the console with a password proof alone.
RSpec.describe "Demo mode", type: :request do
  around do |example|
    previous = ENV.to_h.slice("DEMO_INSTANCE", "DEMO_ACCOUNTS", "DEMO_PASSWORD", "DEMO_OPERATOR_PASSWORD",
                              "DEMO_RESET_AT", "INSTANCE_OPERATOR_USERNAME")
    ENV.delete("DEMO_INSTANCE")
    ENV.delete("DEMO_ACCOUNTS")
    ENV.delete("DEMO_PASSWORD")
    ENV.delete("DEMO_OPERATOR_PASSWORD")
    ENV.delete("DEMO_RESET_AT")
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def run_in_demo_mode(shared: %w[tom])
    ENV["DEMO_INSTANCE"] = "true"
    ENV["DEMO_ACCOUNTS"] = shared.join(",")
    yield
  end

  it "refuses every credential mutation on a shared account, server-side" do
    run_in_demo_mode do
      tom = create(:user, username: "tom")
      tom.identities.create!(provider: "oidc", issuer: "https://issuer.example", subject: "s",
                             email: tom.email_address, email_verified: true, linked_at: Time.current)
      sign_in_as(tom)

      patch settings_security_password_path, params: { user: { current_password: "allure-test-password",
                                                     password: "hijacked-password", password_confirmation: "hijacked-password" } }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("demo.account_locked"))
      expect(tom.reload.authenticate("hijacked-password")).to be_falsey
      expect(tom.authenticate("allure-test-password")).to be_truthy

      post settings_totp_path, params: { code: "123456" }
      expect(response).to redirect_to(root_path)
      expect(tom.reload.totp_enrolled?).to be(false)

      post settings_passkeys_path, params: { credential: "forged" }
      expect(response).to redirect_to(root_path)
      expect(tom.webauthn_credentials).to be_empty

      post settings_recovery_codes_path
      expect(response).to redirect_to(root_path)
      expect(tom.recovery_codes).to be_empty

      delete settings_identity_path(tom.identities.sole)
      expect(response).to redirect_to(root_path)
      expect(tom.identities).to be_present

      post settings_account_deletion_path, params: { deletion: { username: "tom", acknowledged: "1" } }
      expect(response).to redirect_to(root_path)
      expect(tom.reload).not_to be_deletion_scheduled
    end
  end

  it "leaves every other account's credentials alone in demo mode" do
    run_in_demo_mode do
      visitor = create(:user)
      sign_in_as(visitor)

      patch settings_security_password_path, params: { user: { current_password: "allure-test-password",
                                                      password: "a-new-password-123", password_confirmation: "a-new-password-123" } }
      expect(response).to redirect_to(settings_security_path)
      expect(visitor.reload.authenticate("a-new-password-123")).to be_truthy
    end
  end

  it "never persists a session IP address in demo mode" do
    tom = create(:user, username: "tom")
    sign_in_as(tom)
    expect(Session.sole.ip_address).to be_present

    Session.delete_all
    run_in_demo_mode { sign_in_as(tom.reload) }

    expect(Session.sole.ip_address).to be_nil
  end

  it "opens the operator console for a password-only operator, and only in demo mode" do
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"

    marie = create(:user, username: "marie")
    sign_in_as(marie)
    get admin_root_path
    # Outside demo mode an unenrolled operator signs in enrolment-only, and
    # the console is out of reach until a factor exists.
    expect(response).to redirect_to(settings_security_path)

    run_in_demo_mode do
      sign_in_as(marie.reload)
      get admin_root_path
      # The fresh password sign-in is itself the recent proof of identity the
      # console's step-up accepts in demo mode.
      expect(response).to have_http_status(:ok)
    end
  end

  it "carries the reset strip on every page, with the auto-warning's data" do
    tom = create(:user, username: "tom")
    sign_in_as(tom)

    get me_path
    expect(response.body).not_to include("demo-strip")

    run_in_demo_mode do
      ENV["DEMO_RESET_AT"] = "03:00"

      get me_path
      expect(response.body).to include("class=\"demo-strip")
      expect(response.body).to include("data-controller=\"demo-reset\"")
      expect(response.body).to include("data-demo-reset-window-value=\"300\"")
      # The warning line waits, hidden, for the controller to reveal it.
      expect(response.body).to include("data-demo-reset-target=\"warning\"")
      expect(response.body).to include("d-none\" data-demo-reset-target")
      expect(response.body).to include(I18n.t("demo.strip.reset", time: "03:00"))
      expect(response.body).to include(I18n.t("demo.strip.warning"))
    end
  end

  it "publishes the demo credentials on the sign-in page" do
    ENV["INSTANCE_OPERATOR_USERNAME"] = "marie"
    ENV["DEMO_PASSWORD"] = "allure-dev-password"
    ENV["DEMO_OPERATOR_PASSWORD"] = "operator-password-2026"
    create(:user, username: "tom", email_address: "tom@allure.test")
    create(:user, username: "marie", email_address: "marie@allure.test")

    get new_session_path
    expect(response.body).not_to include("demo-credentials")

    run_in_demo_mode do
      get new_session_path
      expect(response.body).to include(I18n.t("demo.credentials.title"))
      # The floating language and theme controls move below the strip instead
      # of overlapping it (DESIGN.md §20.21).
      expect(response.body).to include("demo-strip-offset")
      # The sentence's apostrophe is HTML-escaped; assert its stable head.
      expect(response.body).to include(I18n.t("demo.credentials.sentence").split("N")[0].strip)
      expect(response.body).to include("tom@allure.test")
      expect(response.body).to include(I18n.t("demo.credentials.member"))
      expect(response.body).not_to include("marie@allure.test")
      expect(response.body).not_to include(I18n.t("demo.credentials.admin"))
      expect(response.body).not_to include("operator-password-2026")
      expect(response.body).to include("allure-dev-password")
    end
  end
end
