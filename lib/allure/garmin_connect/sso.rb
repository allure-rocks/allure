# frozen_string_literal: true

module Allure
  module GarminConnect
    # Signs in to Garmin SSO as the Garmin Connect mobile application and
    # returns a CAS service ticket (docs/dev/REMOTE-IMPORTS.md).
    #
    # Port of python-garminconnect 0.3.11 strategies 2 (mobile, plain HTTP) and
    # 5 (portal, plain HTTP), in that order. No TLS impersonation: Garmin's bot
    # protection may refuse a server address, which surfaces as
    # `Error::Refused` once both strategies have been tried.
    #
    # An MFA challenge returns `MfaRequired`, whose `to_h` is the whole state
    # needed to finish later (cookies included); the caller stores it encrypted
    # and passes it back to `verify_mfa`. The password is never kept.
    class Sso
      IOS_CLIENT_ID = "GCM_IOS_DARK"
      PORTAL_CLIENT_ID = "GarminConnect"
      IOS_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) " \
                       "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
      DESKTOP_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
                           "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
      JSON_ACCEPT = "application/json, text/plain, */*"
      # Cloudflare flags a fast sign-in page GET followed by the login POST.
      PORTAL_DELAY = (10.0..20.0)
      STRATEGIES = %i[mobile portal].freeze
      # A 429 stops the chain: Garmin limits sign-ins per account and address,
      # and another attempt only prolongs the block (observed 2026-10-09).
      FALL_THROUGH = [ Error::Refused, Error::Unavailable ].freeze

      SignedIn = Data.define(:ticket, :service_url, :strategy)
      MfaRequired = Data.define(:flow, :method, :service_url, :cookies) do
        def self.from_h(hash)
          hash = hash.transform_keys(&:to_s)
          new(flow: hash.fetch("flow").to_s, method: hash.fetch("method").to_s,
              service_url: hash.fetch("service_url").to_s, cookies: hash.fetch("cookies").to_h)
        end
      end
      Attempt = Data.define(:strategy, :outcome)

      attr_reader :region, :attempts

      def initialize(region: Region.new, sleeper: ->(seconds) { sleep(seconds) }, random: Random.new)
        @region = region
        @sleeper = sleeper
        @random = random
        @attempts = []
      end

      # Returns `SignedIn` or `MfaRequired`; raises `Error::InvalidCredentials`
      # at once, or the last strategy's error when every strategy failed.
      def sign_in(email:, password:)
        @attempts = []
        last_error = nil
        STRATEGIES.each do |strategy|
          result = public_send(:"#{strategy}_sign_in", email, password)
          record(strategy, result.is_a?(MfaRequired) ? "mfa_required" : "successful")
          return result
        rescue Error::InvalidCredentials, Error::RateLimited => error
          record(strategy, error.message)
          raise error
        rescue *FALL_THROUGH => error
          record(strategy, error.message)
          last_error = error
        end
        raise last_error
      end

      def mobile_sign_in(email, password)
        http = new_http
        response = http.post_json("#{region.sso_base}/mobile/api/login",
                                  params: mobile_params, headers: mobile_headers,
                                  body: credentials(email, password))
        interpret(response, http:, flow: "mobile", service_url: region.ios_service_url, strategy: :mobile)
      end

      def portal_sign_in(email, password)
        http = new_http
        page = http.get(portal_signin_url,
                        params: { clientId: PORTAL_CLIENT_ID, service: region.portal_service_url },
                        headers: {
                          "User-Agent" => DESKTOP_USER_AGENT,
                          "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                          "Accept-Language" => "en-US,en;q=0.9"
                        })
        raise Error::RateLimited, "portal sign-in page: HTTP 429" if page.status == 429
        raise Error::Refused, "portal sign-in page: HTTP #{page.status}" unless page.success?

        @sleeper.call(@random.rand(PORTAL_DELAY))
        response = http.post_json("#{region.sso_base}/portal/api/login",
                                  params: portal_params, headers: portal_headers,
                                  body: credentials(email, password))
        interpret(response, http:, flow: "portal", service_url: region.portal_service_url, strategy: :portal)
      end

      # Completes an MFA challenge with the stored state. Tries the flow's own
      # endpoint, then the other one (separate rate-limit buckets upstream).
      def verify_mfa(state:, code:)
        state = MfaRequired.from_h(state) if state.is_a?(Hash)
        http = new_http(cookies: state.cookies)
        body = {
          mfaMethod: state.method, mfaVerificationCode: code.to_s.strip,
          rememberMyBrowser: true, reconsentList: [], mfaSetup: false
        }
        headers = state.flow == "mobile" ? mobile_headers : portal_headers
        endpoints = [ state.flow, (state.flow == "mobile" ? "portal" : "mobile") ]

        failures = []
        rate_limited = 0
        endpoints.each do |path|
          params = path == "mobile" ? mobile_params : portal_params
          response = begin
            http.post_json("#{region.sso_base}/#{path}/api/mfa/verifyCode", params:, headers:, body:)
          rescue Error::Unavailable => error
            failures << "#{path}: #{error.message}"
            next
          end
          json = response.json

          if response.status == 429 || (json.is_a?(Hash) && dig(json, "error", "status-code").to_s == "429")
            rate_limited += 1
            failures << "#{path}: rate limited"
            next
          end
          unless json.is_a?(Hash)
            failures << "#{path}: HTTP #{response.status} non-JSON"
            next
          end

          if response_type(json) == "SUCCESSFUL"
            return SignedIn.new(ticket: json.fetch("serviceTicketId").to_s, service_url: state.service_url,
                                strategy: :"#{state.flow}_mfa")
          end

          failures << "#{path}: #{response_type(json) || dig(json, 'error', 'status-code') || 'unknown'}"
        end

        raise Error::RateLimited, "MFA verification rate limited: #{failures.join(', ')}" if rate_limited == endpoints.length

        raise Error::MfaFailed, "MFA verification failed: #{failures.join(', ')}"
      end

      private

      def interpret(response, http:, flow:, service_url:, strategy:)
        raise Error::RateLimited, "#{strategy}: HTTP 429" if response.status == 429
        raise Error::Refused, "#{strategy}: HTTP 403 (bot challenge)" if response.status == 403

        json = response.json
        unless json.is_a?(Hash)
          raise Error::Unavailable, "#{strategy}: HTTP #{response.status}" if response.status >= 500

          raise Error::Refused, "#{strategy}: HTTP #{response.status} non-JSON (bot challenge)"
        end

        case response_type(json)
        when "SUCCESSFUL"
          SignedIn.new(ticket: json.fetch("serviceTicketId").to_s, service_url:, strategy:)
        when "MFA_REQUIRED"
          method = dig(json, "customerMfaInfo", "mfaLastMethodUsed").to_s
          MfaRequired.new(flow:, method: method.empty? ? "email" : method, service_url:, cookies: http.cookies.dup)
        when "INVALID_USERNAME_PASSWORD"
          raise Error::InvalidCredentials, "invalid username or password"
        when "CAPTCHA_REQUIRED"
          raise Error::Refused, "#{strategy}: CAPTCHA required (bot challenge)"
        else
          raise Error::RateLimited, "#{strategy}: 429 in JSON body" if dig(json, "error", "status-code").to_s == "429"

          raise Error::Unavailable, "#{strategy}: HTTP #{response.status}, responseStatus=#{response_type(json) || 'unknown'}"
        end
      end

      def response_type(json)
        type = dig(json, "responseStatus", "type")
        type&.to_s
      end

      def dig(value, *keys)
        keys.reduce(value) { |node, key| node.is_a?(Hash) ? node[key] : nil }
      end

      def credentials(email, password)
        { username: email.to_s.strip, password: password.to_s, rememberMe: true, captchaToken: "" }
      end

      def mobile_params
        { clientId: IOS_CLIENT_ID, locale: "en-US", service: region.ios_service_url }
      end

      def portal_params
        { clientId: PORTAL_CLIENT_ID, locale: "en-US", service: region.portal_service_url }
      end

      def mobile_headers
        { "User-Agent" => IOS_USER_AGENT, "Accept" => JSON_ACCEPT, "Origin" => region.sso_base }
      end

      def portal_headers
        {
          "User-Agent" => DESKTOP_USER_AGENT,
          "Accept" => JSON_ACCEPT,
          "Accept-Language" => "en-US,en;q=0.9",
          "Origin" => region.sso_base,
          "Referer" => "#{portal_signin_url}?clientId=#{PORTAL_CLIENT_ID}&service=#{region.portal_service_url}"
        }
      end

      def portal_signin_url = "#{region.sso_base}/portal/sso/en-US/sign-in"

      def new_http(cookies: {})
        Http.new(allowed_hosts: region.hosts, cookies:)
      end

      def record(strategy, outcome)
        @attempts << Attempt.new(strategy:, outcome:)
      end
    end
  end
end
