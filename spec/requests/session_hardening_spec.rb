# frozen_string_literal: true

require "rails_helper"

# docs/dev/AUTH.md: session lifetimes and re-authentication before a
# sensitive action.
RSpec.describe "Session hardening" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def sign_in
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  def current_session = user.sessions.order(:created_at).last

  # The test environment verifies no authenticity token, so none is stored.
  def with_forgery_protection
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  describe "lifetimes" do
    it "persists the Rails CSRF session cookie across browser and native app restarts" do
      freeze_time do
        with_forgery_protection do
          get new_session_path

          expect(session[:_csrf_token]).to be_present
          cookie = Array(response.headers["Set-Cookie"]).join("\n")
            .lines.find { |line| line.start_with?("_allure_session=") }
          expect(cookie).to include("expires=#{(Time.current + Allure::Auth::Config.session_max_lifetime).httpdate}")
          expect(cookie).to include("httponly", "samesite=lax")
        end
      end
    end

    it "issues a cookie that ends at the absolute lifetime instead of a permanent one" do
      freeze_time do
        sign_in

        cookie = response.headers["Set-Cookie"].then { |value| Array(value).join("\n") }
          .lines.find { |line| line.start_with?("session_id=") }
        expect(cookie).to include("expires=#{(Time.current + 90.days).httpdate}")
      end
    end

    it "counts the sign-in as a recent proof of identity" do
      sign_in

      expect(current_session.reauthenticated_at).to be_within(5.seconds).of(Time.current)
    end

    it "rotates the CSRF token at sign-in (docs/dev/AUTH.md)" do
      with_forgery_protection do
        get new_session_path
        token = response.parsed_body.at_css('input[name="authenticity_token"]')["value"]
        before = session[:_csrf_token]
        expect(before).to be_present

        post session_path, params: { email_address: user.email_address, password: "allure-test-password",
                                     authenticity_token: token }
        expect(response).to redirect_to(me_path)
        get me_path

        expect(session[:_csrf_token]).to be_present
        expect(session[:_csrf_token]).not_to eq(before)
      end
    end

    it "closes a session idle for longer than the idle timeout" do
      sign_in
      session = current_session

      travel 31.days do
        get settings_security_path

        expect(response).to redirect_to(new_session_path)
        expect(Session.exists?(session.id)).to be(false)
      end
    end

    # The cookie itself ends at the lifetime it was issued with; a shorter
    # lifetime configured afterwards is enforced on the server.
    it "closes a session at its absolute lifetime even while it is used" do
      sign_in
      session = current_session
      previous = ENV["AUTH_SESSION_MAX_DAYS"]
      ENV["AUTH_SESSION_MAX_DAYS"] = "60"

      (1..2).each do |month|
        travel_to(session.created_at + (month * 29).days) { get settings_security_path }
      end
      expect(response).to have_http_status(:ok)

      travel_to(session.created_at + 60.days + 1.second) do
        get settings_security_path

        expect(response).to redirect_to(new_session_path)
        expect(Session.exists?(session.id)).to be(false)
      end
    ensure
      ENV["AUTH_SESSION_MAX_DAYS"] = previous
    end

    it "records activity on use" do
      sign_in
      session = current_session

      travel 1.hour do
        get settings_security_path

        expect(session.reload.last_seen_at).to be_within(5.seconds).of(Time.current)
      end
    end

    it "shows the sign-in time and the lifetime rule on the sessions card" do
      sign_in

      get settings_security_path

      headers = response.parsed_body.css("table[aria-labelledby='sessions-title'] th").map { |th| th.text.strip }
      expect(headers).to include("Connexion")
      expect(response.parsed_body.at_css("table[aria-labelledby='sessions-title'] tbody").text).to include("Mot de passe")
      expect(response.body).to include("Une session se ferme après 30 jours sans activité, et au plus tard 90 jours après la connexion.")
    end
  end

  describe "re-authentication" do
    let!(:other) { user.sessions.create!(user_agent: "Other", ip_address: "10.0.0.2") }

    before { sign_in }

    it "lets a fresh sign-in close another session directly" do
      delete settings_security_session_path(other)

      expect(response).to redirect_to(settings_security_path)
      expect(Session.exists?(other.id)).to be(false)
    end

    context "once the window has passed" do
      before { travel 11.minutes }
      after { travel_back }

      it "asks for the password before closing another session" do
        delete settings_security_session_path(other, page: 2), headers: { "Referer" => settings_security_url(page: 2) }

        expect(response).to redirect_to(new_reauthentication_path)
        expect(response).to have_http_status(:see_other)
        expect(Session.exists?(other.id)).to be(true)

        follow_redirect!
        expect(response.body).to include("Confirmez votre identité", "10 minutes", user.email_address)
        expect(response.parsed_body.at_css("a[href='#{settings_security_url(page: 2)}']")).to be_present
      end

      it "asks for the password before signing out everywhere" do
        delete settings_destroy_all_security_sessions_path

        expect(response).to redirect_to(new_reauthentication_path)
        expect(user.sessions.count).to eq(2)
      end

      it "refuses a wrong password" do
        delete settings_destroy_all_security_sessions_path
        post reauthentication_path, params: { password: "wrong-password" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Ce mot de passe ne correspond pas.")
        expect(current_session.reload).not_to be_recently_authenticated
      end

      it "returns to the page the action came from once confirmed" do
        delete settings_security_session_path(other), headers: { "Referer" => settings_security_url(sort: "device_asc") }
        post reauthentication_path, params: { password: "allure-test-password" }

        expect(response).to redirect_to(settings_security_url(sort: "device_asc"))
        expect(flash[:notice]).to eq("Identité confirmée. Vous pouvez reprendre votre action.")

        delete settings_security_session_path(other)
        expect(Session.exists?(other.id)).to be(false)
      end

      it "ignores a referer from another host" do
        delete settings_security_session_path(other), headers: { "Referer" => "https://evil.example/steal" }
        post reauthentication_path, params: { password: "allure-test-password" }

        expect(response).to redirect_to(settings_security_path)
      end

      it "counts a password change as a proof of identity" do
        patch settings_security_password_path, params: {
          user: { current_password: "allure-test-password",
                  password: "rotated-password-1", password_confirmation: "rotated-password-1" }
        }

        expect(current_session.reload).to be_recently_authenticated
      end
    end

    it "requires a session" do
      delete session_path
      get new_reauthentication_path

      expect(response).to redirect_to(new_session_path)
    end

    it "renders in English" do
      user.update!(locale: "en")
      get new_reauthentication_path

      expect(response.body).to include("Confirm your identity", "This confirmation stays valid for 10 minutes.")
    end
  end
end
