# frozen_string_literal: true

require "date"

module Allure
  module StravaArchive
    # Reads the `Activity Date` of `activities.csv`
    # (docs/dev/STRAVA-ARCHIVE.md). Strava writes it in UTC but in the athlete's display
    # language: `Aug 31, 2014, 10:54:43 AM`, `09.12.2022, 15:24:49`,
    # `9 déc. 2022, 15:24:49`, `2022年12月9日 下午3:24:49`. The reader looks
    # for its parts rather than one pattern per language: an ISO date, a
    # numeric day-month-year, a month name of the listed languages, or a
    # year-first date; then the last clock time and an afternoon marker. An
    # unreadable value is nil, never a guess.
    module Dates
      MONTHS = {
        # English, French, German, Spanish, Italian, Dutch, Portuguese.
        "jan" => 1, "janv" => 1, "ene" => 1, "gen" => 1,
        "feb" => 2, "fev" => 2, "fevr" => 2,
        "mar" => 3, "mars" => 3, "maa" => 3, "mrt" => 3,
        "apr" => 4, "avr" => 4, "abr" => 4,
        "may" => 5, "mai" => 5, "mag" => 5, "mei" => 5,
        "jun" => 6, "juin" => 6, "giu" => 6,
        "jul" => 7, "juil" => 7, "lug" => 7,
        "aug" => 8, "aout" => 8, "ago" => 8,
        "sep" => 9, "sept" => 9, "set" => 9,
        "oct" => 10, "okt" => 10, "ott" => 10, "out" => 10,
        "nov" => 11,
        "dec" => 12, "dez" => 12, "dic" => 12
      }.freeze
      AFTERNOON = /(?:\bpm\b|\bp\.\s?m\.|下午|午後|오후)/
      MORNING = /(?:\bam\b|\ba\.\s?m\.|上午|午前|오전)/
      TIME = /(\d{1,2}):(\d{2})(?::(\d{2}))?/

      module_function

      def parse(value)
        text = normalize(value)
        return nil if text.empty?

        year, month, day = date_parts(text)
        return nil unless year && Date.valid_date?(year, month, day)

        hour, minute, second = time_parts(text)
        return nil unless hour < 24 && minute < 60 && second < 60

        Time.utc(year, month, day, hour, minute, second)
      rescue ArgumentError, RangeError
        nil
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/[[:space:]]+/, " ").strip
      end

      def date_parts(text)
        if (match = text.match(/(\d{4})-(\d{1,2})-(\d{1,2})/))
          return [ match[1], match[2], match[3] ].map(&:to_i)
        end
        if (match = text.match(%r{\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b}))
          return numeric_date(match[1].to_i, match[2].to_i, match[3].to_i)
        end

        named_date(text) || year_first_date(text)
      end

      # Day first, as every listed language but US English writes it; US
      # English names the month. A first number over 12 settles it anyway.
      def numeric_date(first, second, year)
        second > 12 && first <= 12 ? [ year, first, second ] : [ year, second, first ]
      end

      def named_date(text)
        date_text = text.sub(TIME, " ")
        month = date_text.scan(/\p{L}+/).filter_map { |word| month_for(word) }.first
        year = date_text[/\b(\d{4})\b/, 1]
        return nil unless month && year

        day = date_text.scan(/\b(\d{1,2})\b/).flatten.map(&:to_i).find { |number| number.between?(1, 31) }
        day && [ year.to_i, month, day ]
      end

      def month_for(word)
        MONTHS[word[0, 4]] || MONTHS[word[0, 3]]
      end

      def year_first_date(text)
        match = text.match(/(\d{4})\D{1,3}(\d{1,2})\D{1,3}(\d{1,2})/)
        match && [ match[1], match[2], match[3] ].map(&:to_i)
      end

      def time_parts(text)
        match = text.scan(TIME).last
        return [ 0, 0, 0 ] unless match

        hour = match[0].to_i
        if text.match?(AFTERNOON) && hour < 12
          hour += 12
        elsif text.match?(MORNING) && hour == 12
          hour = 0
        end
        [ hour, match[1].to_i, match[2].to_i ]
      end
    end
  end
end
