# frozen_string_literal: true

require "rails_helper"

# M4 Slice 1 proofs: rebuilt auth surfaces, open registration with a closed
# branch, bilingual mailers, and the settings security page. Every user-visible
# string is asserted in French (default) with English spot checks.
RSpec.describe "Slice 1 authentication" do
  let(:user) { create(:user) }

  def sign_in_as(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  describe "sign-in" do
    it "renders the rebuilt shell with recovery and sign-up links" do
      get new_session_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Connexion", "Mot de passe oublié ?", "Créer un compte")
      expect(response.body).to include(%(href="#{new_registration_path}"))
      expect(response.body).not_to include('style="color:red"')
    end

    it "renders a summary alert and keeps the email on bad credentials" do
      post session_path, params: { email_address: user.email_address, password: "wrong-password" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Essayez une autre adresse")
      expect(response.body).to include(%(value="#{user.email_address}"))
    end

    it "signs in with valid credentials" do
      post session_path, params: { email_address: user.email_address, password: "allure-test-password" }

      expect(response).to redirect_to(me_url)
    end

    # `User.authenticate_by` raises when the password key is absent; the form
    # answers a crafted POST like any other failed sign-in instead of a 500.
    it "answers a request missing the password like a failed sign-in" do
      post session_path, params: { email_address: user.email_address }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Essayez une autre adresse")
    end

    it "answers an empty sign-in request without an error" do
      post session_path, params: {}

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "renders in English on request" do
      get new_session_path(locale: "en")

      expect(response.body).to include("Forgot password?", "Create an account")
    end
  end

  describe "auth chrome and fields" do
    # Rails' password_field maps maxlength to size when no explicit size is
    # given; the browser then renders the input at that character width instead
    # of full width. Regression for the session/registration/reset forms.
    it "renders full-width password fields without a size attribute" do
      [ new_session_path, new_registration_path, edit_password_path(user.password_reset_token) ].each do |path|
        get path

        expect(response.body).not_to match(/<input[^>]*type="password"[^>]*\bsize=/)
      end
    end

    # The same Rails mapping would widen the settings security fields past a
    # phone viewport; the settings shell verification pinned it here too.
    it "renders full-width settings security fields without a size attribute" do
      sign_in_as
      get settings_security_path

      expect(response.body).not_to match(/<input[^>]*type="password"[^>]*\bsize=/)
    end

    it "uses the minimal auth shell instead of the application chrome" do
      get new_session_path

      expect(response.body).to include("page-center")
      expect(response.body).not_to include("navbar-expand-lg", 'id="primary-menu"', "bottom-bar-item")
    end

    it "offers a bilingual password reveal toggle" do
      get new_session_path

      expect(response.body).to include("data-controller=\"password-visibility\"")
      expect(response.body).to include(%(aria-label="#{I18n.t("forms.password.show")}"))
      expect(response.body).to include("ti-eye")
    end
  end

  describe "registration" do
    it "renders the sign-up form with username guidance and live availability" do
      get new_registration_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Créer un compte", "30 caractères maximum", "Certains noms sont réservés")
      expect(response.body).to include("data-controller=\"availability\"")
      expect(response.body).to include(%(data-availability-url-value="#{availability_registration_path}"))
    end

    it "creates the account and signs in" do
      expect do
        post registration_path, params: {
          user: { username: "newrider", email_address: "newrider@allure.test",
                  password: "allure-test-password", password_confirmation: "allure-test-password" }
        }
      end.to change(User, :count).by(1)

      expect(response).to redirect_to(me_url)
      follow_redirect!
      expect(response.body).to include("Bienvenue sur Allure")
    end

    it "renders inline and summary errors on invalid input" do
      post registration_path, params: {
        user: { username: "admin", email_address: "not-an-email",
                password: "allure-test-password", password_confirmation: "mismatch" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('role="alert"', "is-invalid")
    end

    it "rejects a duplicate email address without a server error" do
      existing = create(:user)

      post registration_path, params: {
        user: { username: "anotherrider", email_address: existing.email_address.upcase,
                password: "allure-test-password", password_confirmation: "allure-test-password" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("déjà utilisée")
      expect(User.count).to eq(1)
    end

    it "rejects a malformed email address" do
      post registration_path, params: {
        user: { username: "anotherrider", email_address: "not-an-email",
                password: "allure-test-password", password_confirmation: "allure-test-password" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("adresse e-mail valide")
    end

    it "rejects a password shorter than the NIST minimum" do
      post registration_path, params: {
        user: { username: "shortpass", email_address: "shortpass@allure.test",
                password: "too-short", password_confirmation: "too-short" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("au moins 15 caractères")
      expect(User.count).to eq(0)
    end

    it "states the minimum password length in the form" do
      get new_registration_path

      expect(response.body).to include("Au moins 15 caractères", %(minlength="#{User::MINIMUM_PASSWORD_LENGTH}"))
    end

    it "reports username availability as JSON" do
      get availability_registration_path, params: { username: "freshname" }, headers: { "Accept" => "application/json" }
      expect(response.parsed_body).to eq({ "available" => true, "reason" => nil })

      get availability_registration_path, params: { username: user.username }, headers: { "Accept" => "application/json" }
      expect(response.parsed_body["available"]).to be(false)
      expect(response.parsed_body["reason"]).to be_present

      get availability_registration_path, params: { username: "admin" }, headers: { "Accept" => "application/json" }
      expect(response.parsed_body["available"]).to be(false)

      get availability_registration_path, params: { username: "www" }, headers: { "Accept" => "application/json" }
      expect(response.parsed_body["available"]).to be(false)
      expect(response.parsed_body["reason"]).to include("réservé")
    end

    context "when the configured operator account does not exist yet" do
      around do |example|
        previous = ENV["INSTANCE_OPERATOR_USERNAME"]
        ENV["INSTANCE_OPERATOR_USERNAME"] = "Ops "
        example.run
      ensure
        ENV["INSTANCE_OPERATOR_USERNAME"] = previous
      end

      it "refuses to hand the operator name to a self-registration" do
        expect do
          post registration_path, params: {
            user: { username: "ops", email_address: "ops@allure.test",
                    password: "allure-test-password", password_confirmation: "allure-test-password" }
          }
        end.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("réservé")

        get availability_registration_path, params: { username: "OPS" }, headers: { "Accept" => "application/json" }
        expect(response.parsed_body["available"]).to be(false)
      end
    end

    context "when the instance has its own name" do
      before { allow(Allure::Instance).to receive(:name).and_return("Mon Club") }

      it "refuses the instance's name to a self-registration" do
        expect do
          post registration_path, params: {
            user: { username: "MON_CLUB", email_address: "mon@allure.test",
                    password: "allure-test-password", password_confirmation: "allure-test-password" }
          }
        end.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("réservé")

        get availability_registration_path, params: { username: "mon_club" }, headers: { "Accept" => "application/json" }
        expect(response.parsed_body["available"]).to be(false)
      end
    end

    context "when a deleted account's username is offered again" do
      it "refuses it (docs/dev/ACCOUNT.md)" do
        deleted = create(:user, username: "gone_rider")
        Federation::ActorProvisioner.new(user: deleted).call!
        deleted.destroy!

        expect do
          post registration_path, params: {
            user: { username: "gone_rider", email_address: "back@allure.test",
                    password: "allure-test-password", password_confirmation: "allure-test-password" }
          }
        end.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("appartenu à un compte supprimé")
      end
    end

    context "when registration is closed" do
      before { allow(Allure::Registration).to receive(:open?).and_return(false) }

      it "states so on the sign-in page with no sign-up link" do
        get new_session_path

        expect(response.body).to include("inscriptions sont fermées")
        expect(response.body).not_to include(%(href="#{new_registration_path}"))
      end

      it "blocks the form, creation, and availability" do
        get new_registration_path
        expect(response).to redirect_to(new_session_path)

        expect do
          post registration_path, params: {
            user: { username: "closed", email_address: "closed@allure.test",
                    password: "allure-test-password", password_confirmation: "allure-test-password" }
          }
        end.not_to change(User, :count)

        get availability_registration_path, params: { username: "freshname" }
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "password reset" do
    it "renders the forgot-password shell" do
      get new_password_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mot de passe oublié ?", "Retour à la connexion")
    end

    it "always answers neutrally" do
      post passwords_path, params: { email_address: "unknown@allure.test" }

      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(response.body).to include("si un compte existe")
    end

    # The request path must cost the same for a known and an unknown address:
    # a synchronous lookup-and-enqueue branch leaks account existence through
    # response timing.
    it "enqueues the same reset work for a known and an unknown address" do
      expect { post passwords_path, params: { email_address: user.email_address } }
        .to have_enqueued_job(Users::PasswordResetJob).with(user.email_address)

      expect { post passwords_path, params: { email_address: "unknown@allure.test" } }
        .to have_enqueued_job(Users::PasswordResetJob).with("unknown@allure.test")
    end

    it "renders the reset form from a valid token" do
      get edit_password_path(user.password_reset_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Choisissez un nouveau mot de passe")
    end

    it "rejects an invalid token" do
      get edit_password_path("bogus-token")

      expect(response).to redirect_to(new_password_path)
    end

    # The edit form is built on the user model, so the browser posts its
    # fields under `user`; the specs send exactly that shape.
    it "posts the fields under the user key" do
      get edit_password_path(user.password_reset_token)

      form = response.parsed_body.at_css("form[action^='/passwords/']")
      expect(form.at_css("input[type=password][name='user[password]']")).to be_present
      expect(form.at_css("input[type=password][name='user[password_confirmation]']")).to be_present
    end

    it "resets on matching passwords and closes sessions" do
      sign_in_as
      expect(user.sessions.count).to eq(1)

      put password_path(user.password_reset_token), params: {
        user: { password: "brand-new-password-1", password_confirmation: "brand-new-password-1" }
      }

      expect(response).to redirect_to(new_session_path)
      expect(user.sessions.count).to eq(0)
      expect(user.reload.authenticate("brand-new-password-1")).to be_truthy
      expect(user.authenticate("allure-test-password")).to be(false)
    end

    it "refuses an empty submission without touching the password or the sessions" do
      sign_in_as

      put password_path(user.password_reset_token), params: { user: { password: "", password_confirmation: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.sessions.count).to eq(1)
      expect(user.reload.authenticate("allure-test-password")).to be_truthy
    end

    it "refuses top-level fields the form never sends" do
      put password_path(user.password_reset_token), params: {
        password: "brand-new-password-1", password_confirmation: "brand-new-password-1"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.authenticate("allure-test-password")).to be_truthy
    end

    it "re-renders with errors on mismatch" do
      put password_path(user.password_reset_token), params: {
        user: { password: "one-password-0001", password_confirmation: "another-password-2" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('role="alert"')
      expect(user.reload.authenticate("allure-test-password")).to be_truthy
    end

    it "rejects a new password shorter than the NIST minimum" do
      put password_path(user.password_reset_token), params: {
        user: { password: "too-short", password_confirmation: "too-short" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("au moins 15 caractères")
      expect(user.reload.authenticate("allure-test-password")).to be_truthy
    end
  end

  describe "reset mailer" do
    it "follows the account locale with link, expiry, and ignore note" do
      fr_mail = PasswordsMailer.reset(user).message
      expect(fr_mail.subject).to eq("Réinitialisez votre mot de passe Allure")
      expect(fr_mail.html_part.body.decoded).to include("Réinitialiser mon mot de passe", "ignorez ce message")

      user.update!(locale: "en")
      en_mail = PasswordsMailer.reset(user).message
      expect(en_mail.subject).to eq("Reset your Allure password")
      expect(en_mail.text_part.body.decoded).to include("/passwords/", "ignore this message")
    end
  end

  describe "settings security" do
    it "redirects anonymous visitors" do
      get settings_security_path
      expect(response).to redirect_to(new_session_path)
    end

    it "lists sessions with the current one badged" do
      sign_in_as

      get settings_security_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sessions actives", "Cette session")
      expect(response.body).to include("Toutes vos sessions sont fermées")
    end

    it "paginates the sessions table" do
      sign_in_as
      14.times { |index| user.sessions.create!(user_agent: "Agent #{index}", ip_address: "10.0.0.#{index}") }

      get settings_security_path

      expect(response.parsed_body.css("table tbody tr").length).to eq(10)
      links = response.parsed_body.css(".pagination a.page-link").map { |link| link["href"] }
      expect(links).to include(settings_security_path(page: 2))

      get settings_security_path(page: 2)

      expect(response.parsed_body.css("table tbody tr").length).to eq(5)
    end

    it "sorts the sessions table by device and by last seen" do
      sign_in_as
      user.sessions.create!(user_agent: "Alpha browser", ip_address: "10.0.0.2", last_seen_at: 1.hour.ago)
      user.sessions.create!(user_agent: "Zulu browser", ip_address: "10.0.0.3", last_seen_at: 2.hours.ago)

      get settings_security_path(sort: "device_asc")

      readers = response.parsed_body.css("table tbody tr td:first-child").map { |cell| cell.text.squish }
      expect(readers.first).to include("Alpha browser")
      expect(response.parsed_body.at_css('th[aria-sort="ascending"]')).to be_present

      get settings_security_path(sort: "last_seen_asc")

      readers = response.parsed_body.css("table tbody tr td:first-child").map { |cell| cell.text.squish }
      expect(readers.first).to include("Zulu browser")
      expect(response.parsed_body.at_css('th[aria-sort="ascending"]')).to be_present
    end

    it "keeps the page and the sort after revoking a session" do
      sign_in_as
      other = user.sessions.create!(user_agent: "Other", ip_address: "10.0.0.2")

      delete settings_security_session_path(other, page: 2, sort: "device_asc")

      expect(response).to redirect_to(settings_security_path(page: 2, sort: "device_asc"))
      expect(user.sessions.exists?(other.id)).to be(false)
    end

    it "changes the password with the current one and closes other sessions" do
      sign_in_as
      post session_path, params: { email_address: user.email_address, password: "allure-test-password" }

      patch settings_security_password_path, params: {
        user: { current_password: "allure-test-password",
                password: "rotated-password-1", password_confirmation: "rotated-password-1" }
      }

      expect(response).to redirect_to(settings_security_path)
      expect(user.sessions.count).to eq(1)
      expect(user.reload.authenticate("rotated-password-1")).to be_truthy
    end

    it "rejects a wrong current password without changing anything" do
      sign_in_as

      patch settings_security_password_path, params: {
        user: { current_password: "wrong-password",
                password: "rotated-password-1", password_confirmation: "rotated-password-1" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('role="alert"')
      expect(user.reload.authenticate("allure-test-password")).to be_truthy
    end

    it "rejects a new password shorter than the NIST minimum" do
      sign_in_as

      patch settings_security_password_path, params: {
        user: { current_password: "allure-test-password",
                password: "too-short", password_confirmation: "too-short" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("au moins 15 caractères")
      expect(user.reload.authenticate("allure-test-password")).to be_truthy
    end

    it "revokes another session but not the current one individually" do
      sign_in_as
      other = user.sessions.create!(user_agent: "Other", ip_address: "10.0.0.2")
      current = user.sessions.order(:created_at).first

      delete settings_security_session_path(current)
      expect(response).to redirect_to(settings_security_path)
      expect(user.sessions.count).to eq(2)

      delete settings_security_session_path(other)
      expect(response).to redirect_to(settings_security_path)
      expect(user.sessions.count).to eq(1)
    end

    it "signs out everywhere" do
      sign_in_as

      delete settings_destroy_all_security_sessions_path

      expect(response).to redirect_to(new_session_path)
      expect(user.sessions.count).to eq(0)
    end
  end
end
