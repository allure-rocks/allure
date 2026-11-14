# frozen_string_literal: true

module Allure
  module Exr
    # Signs in to the EXR account site once and returns the remember cookie,
    # the only credential Allure keeps (PLAN_REMOTE_IMPORTS.md §7b.2). The
    # sign-in is the site's own HTML form: `GET /login` for the CSRF `_token`
    # and the session cookies, then `POST /login` with `mail` and `password`.
    class Session
      REMEMBER_PREFIX = "remember_web_"
      LOGIN_PATH = "/login"

      def self.remember_cookie(cookies)
        Array(cookies).find { |cookie| cookie.name.start_with?(REMEMBER_PREFIX) }
      end

      # True when a redirect target or a page is the sign-in form.
      def self.login_location?(location)
        URI.parse(location.to_s).path.to_s.chomp("/").end_with?(LOGIN_PATH)
      rescue URI::InvalidURIError
        false
      end

      attr_reader :http

      def initialize(http: Http.new)
        @http = http
      end

      # Returns the remember cookie (`Http::Cookie`), or raises.
      def sign_in(email:, password:)
        token = csrf_token(@http.get(LOGIN_PATH))
        response = @http.post_form(LOGIN_PATH, form: { "_token" => token, "mail" => email.to_s, "password" => password.to_s })
        check_sign_in(response)

        self.class.remember_cookie(@http.cookies) ||
          raise(Error::NoRememberCookie, "the sign-in set no remember cookie")
      end

      private

      def csrf_token(response)
        raise Error::RateLimited, "sign-in page: HTTP 429" if response.status == 429
        raise Error::Unavailable, "sign-in page: HTTP #{response.status}" unless response.success?

        token = SessionsPage.document(response.body).at_css('form input[name="_token"]')&.[]("value")
        raise Error::Unavailable, "sign-in page without a CSRF token" if token.to_s.empty?

        token
      end

      def check_sign_in(response)
        raise Error::RateLimited, "sign-in: HTTP 429" if response.status == 429
        raise Error::Unavailable, "sign-in: HTTP #{response.status}" unless response.redirect?
        raise Error::InvalidCredentials, "the site refused the sign-in" if self.class.login_location?(response.location)
      end
    end
  end
end
