# frozen_string_literal: true

module Allure
  module Exr
    # Reads a signed-in EXR account with nothing but its remember cookie
    # (docs/dev/REMOTE-IMPORTS.md): the session list, page by page, and each
    # session's FIT file. Only GET requests are sent. A landing on the sign-in
    # page raises `Error::SignedOut`; a remember cookie the site replaces is
    # handed to `on_rotate` before the next request.
    class Client
      MAX_PAGES = 50
      MAX_FIT_BYTES = 16 * 1024 * 1024
      FIT_SIGNATURE = ".FIT"

      attr_reader :remember

      def initialize(remember:, http: nil, on_rotate: nil)
        @remember = remember
        @http = http || Http.new(cookies: [ remember ])
        @on_rotate = on_rotate
      end

      def page(number = 1)
        response = get(number.to_i > 1 ? "/sessions/#{number.to_i}" : "/sessions")
        check(response, "session list")
        page = SessionsPage.parse(response.body)
        raise Error::SignedOut, "the session list answered the sign-in form" if page.signed_out?

        @session_ready = true
        page
      end

      # Rows whose listed date falls in `from..to` (dates of the listed,
      # zone-less time), newest first. Stops at the first page older than
      # `from`.
      def list(from:, to:, max_pages: MAX_PAGES)
        rows = []
        number = 1
        max_pages.times do
          page = page(number)
          rows.concat(page.rows.select { |row| row.listed_at && (from..to).cover?(row.listed_at.to_date) })
          oldest = page.rows.filter_map(&:listed_at).min
          break if page.next_page.nil? || oldest.nil? || oldest.to_date < from

          number = page.next_page
        end
        rows
      end

      # Streams the session's FIT file into `io` and checks its header.
      def download_fit(uuid, io:)
        raise ArgumentError, "not a session id" unless SessionsPage::UUID.match?(uuid.to_s)

        # The remember cookie opens the list, but EXR's FIT export needs the
        # session cookies it establishes (otherwise the site answers HTTP 500).
        page unless @session_ready
        response = @http.download("/sessions/download/fit/#{uuid}", io:, max_bytes: MAX_FIT_BYTES)
        raise Error::NotFound, "session #{uuid}: HTTP 404" if response.status == 404

        check(response, "FIT download")
        io.rewind
        header = io.read(12).to_s
        io.rewind
        raise Error::SignedOut, "the download answered a page, not a FIT file" unless header.byteslice(8, 4) == FIT_SIGNATURE

        io
      end

      private

      MAX_REDIRECTS = 2

      # Follows the site's own redirects (a trailing slash, a locale), never
      # the one to the sign-in page, which `check` reports as signed out.
      def get(path)
        response = @http.get(path)
        MAX_REDIRECTS.times do
          break unless response.redirect? && !Session.login_location?(response.location)

          response = @http.get(response.location)
        end
        response
      rescue ArgumentError
        raise Error::Unavailable, "redirected off the EXR account site"
      end

      def check(response, what)
        track_rotation
        raise Error::SignedOut, "#{what}: redirected to the sign-in page" if
          response.redirect? && Session.login_location?(response.location)
        raise Error::RateLimited, "#{what}: HTTP 429" if response.status == 429
        raise Error::Unavailable, "#{what}: HTTP #{response.status}" unless response.success?
      end

      def track_rotation
        current = Session.remember_cookie(@http.cookies)
        return if current.nil? || current.value == @remember.value

        @remember = current
        @on_rotate&.call(current)
      end
    end
  end
end
