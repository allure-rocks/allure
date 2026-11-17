# frozen_string_literal: true

require "nokogiri"

module Allure
  module Exr
    # One page of the EXR account's session list (`/sessions/` or
    # `/sessions/<n>`), newest first (docs/dev/REMOTE-IMPORTS.md). The page
    # is translated, so the parser reads attributes and numbers, never labels.
    #
    # `listed_at` keeps the site's `datetime` as written, which carries no
    # zone: it is built as a UTC time from those digits, and the caller
    # applies the offset the probe established.
    class SessionsPage
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      DATETIME = /\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?\z/
      DURATION = /\A(?:(\d+):)?(\d{1,2}):(\d{2})\z/
      DISTANCE = /\A([\d.,]+)\s*(km|mi|m)\z/i
      UNIT_METRES = { "km" => 1000.0, "mi" => 1609.344, "m" => 1.0 }.freeze
      PAGE_PATH = %r{/sessions/(\d+)\z}
      TITLE_PREFIX = /\AEXR\s*\|\s*/

      Row = Data.define(:uuid, :listed_at, :title, :distance_m, :duration_s)

      def self.document(html) = Nokogiri::HTML5(html.to_s)

      def self.parse(html) = new(document(html))

      def initialize(document)
        @document = document
      end

      def rows
        @rows ||= @document.css("table.tableSessions tbody tr").filter_map { |tr| row(tr) }
      end

      # True when the site answered the sign-in form instead of the list.
      def signed_out?
        @document.at_css('form[action$="/login"] input[name="password"]') ? true : false
      end

      def next_page
        href = @document.at_css("ul.pagination li.paginationNext a")&.[]("href")
        page_number(href)
      end

      def last_page
        @document.css("ul.pagination a").filter_map { |link| page_number(link["href"]) }.max || 1
      end

      private

      def row(tr)
        uuid = tr.at_css("input.checkSingle")&.[]("value").to_s
        return nil unless UUID.match?(uuid)

        Row.new(
          uuid:,
          listed_at: listed_at(tr.at_css("td time[datetime]")&.[]("datetime")),
          title: title(tr.at_css("label")),
          distance_m: distance(tr),
          duration_s: duration(tr)
        )
      end

      def listed_at(value)
        match = DATETIME.match(value.to_s.strip)
        match && Time.utc(*match.captures.first(5).map(&:to_i), match[6].to_i)
      end

      def title(label)
        text = (label&.[]("title") || label&.text).to_s.strip
        text = text.sub(TITLE_PREFIX, "")
        text.empty? ? nil : text
      end

      def distance(tr)
        tr.css("td").each do |td|
          match = DISTANCE.match(td.text.tr("\u00A0", " ").strip)
          next unless match

          return (match[1].tr(",", ".").to_f * UNIT_METRES.fetch(match[2].downcase)).round(1)
        end
        nil
      end

      def duration(tr)
        tr.css("td time").each do |time|
          match = DURATION.match(time.text.strip)
          return (match[1].to_i * 3600) + (match[2].to_i * 60) + match[3].to_i if match
        end
        nil
      end

      def page_number(href)
        match = href && PAGE_PATH.match(URI.parse(href).path.to_s)
        match && match[1].to_i
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
