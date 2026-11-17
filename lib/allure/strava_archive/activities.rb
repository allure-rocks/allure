# frozen_string_literal: true

require "csv"

module Allure
  module StravaArchive
    # Reads `activities.csv` from a Strava archive (docs/dev/STRAVA-ARCHIVE.md).
    #
    # Strava writes the headers, the activity types and the dates in the
    # athlete's display language, so no header text is trusted: the leading
    # columns are read by position. Their order has been stable for a decade,
    # except that older archives lack `Activity Private Note`, which shifts the
    # gear and the file one column left; the file column is told apart by its
    # values (`activities/…` or empty). Columns Strava appends at the end are
    # ignored.
    class Activities
      class MalformedError < StandardError; end

      MAX_ACTIVITIES = 10_000
      FILE_PATTERN = %r{\Aactivities/[^/]+\z}
      # The last column, `Media`, lists the activity's photos, `|`-separated
      # (slice 3). Only a plain name, optionally under `media/`, is kept.
      MEDIA_ITEM = %r{\A(?:media/)?([^/\\]+)\z}

      ID = 0
      DATE = 1
      NAME = 2
      TYPE = 3
      DESCRIPTION = 4
      COMMUTE = 9
      CURRENT_FILENAME = 12
      LEGACY_FILENAME = 11
      # The second block of figures, in SI with a dot whatever the language,
      # by offset after the file column (slice 2). The leading `Elapsed Time`
      # is the fallback duration; the leading `Distance` is localized and
      # never read.
      LEADING_ELAPSED = 5
      FIGURE_OFFSETS = {
        "elapsed" => 3, "moving" => 4, "distance" => 5, "ascent" => 8,
        "max_heart_rate" => 18, "average_heart_rate" => 19, "average_power" => 21, "calories" => 22
      }.freeze

      Activity = Data.define(:id, :date, :name, :type_label, :description, :private_note,
                             :commute, :gear_name, :filename, :figures, :media) do
        def file? = filename.present?
      end

      def self.parse(source) = new(source).activities

      def initialize(source)
        @source = source
      end

      def activities
        rows = read_rows
        raise MalformedError, "activities.csv holds no header" if rows.empty?

        body = rows.drop(1).reject { |row| row.compact.empty? }
        raise MalformedError, "activities.csv holds more than #{MAX_ACTIVITIES} activities" if body.length > MAX_ACTIVITIES

        filename_index = filename_column(body)
        body.map { |row| activity(row, filename_index) }
      end

      private

      def read_rows
        text = @source.respond_to?(:read) ? @source.read : @source.to_s
        text = text.dup.force_encoding(Encoding::UTF_8)
        text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless text.valid_encoding?
        CSV.parse(text.delete_prefix("\uFEFF"))
      rescue CSV::MalformedCSVError => error
        raise MalformedError, error.message
      end

      # The current layout unless only the legacy position ever names a file.
      # An archive without a single file (every activity typed by hand) keeps
      # the current layout: its rows are skipped either way.
      def filename_column(body)
        body.each do |row|
          raise MalformedError, "activities.csv row without an activity id" unless row[ID].to_s.strip.match?(/\A\d+\z/)
        end

        return CURRENT_FILENAME if body.any? { |row| file_value?(row[CURRENT_FILENAME]) }
        return LEGACY_FILENAME if body.any? { |row| file_value?(row[LEGACY_FILENAME]) }

        CURRENT_FILENAME
      end

      def activity(row, filename_index)
        legacy = filename_index == LEGACY_FILENAME
        filename = text(row[filename_index])
        Activity.new(
          id: text(row[ID]),
          date: text(row[DATE]),
          name: text(row[NAME]),
          type_label: text(row[TYPE]),
          description: text(row[DESCRIPTION]),
          private_note: legacy ? nil : text(row[COMMUTE + 1]),
          commute: truthy?(row[COMMUTE]),
          gear_name: text(row[filename_index - 1]),
          filename: file_value?(filename) ? filename : nil,
          figures: figures(row, filename_index),
          media: media(row, filename_index)
        )
      end

      # `media/…` names, never the file column itself on a row cut short. A
      # workout holds at most `Photos::Config::MAX_PER_WORKOUT` photos, so
      # the names past it are never extracted.
      def media(row, filename_index)
        return [] unless row.length > filename_index + 1

        row.last.to_s.split("|").filter_map do |item|
          name = item.strip[MEDIA_ITEM, 1]
          "media/#{name}" if name && name != "." && name != ".."
        end.uniq.first(Allure::Photos::Config::MAX_PER_WORKOUT)
      end

      # The figures a row states, in SI: seconds, metres, bpm, watts, kcal.
      def figures(row, filename_index)
        values = FIGURE_OFFSETS.to_h { |name, offset| [ name, number(row[filename_index + offset]) ] }
        values["elapsed"] ||= number(row[LEADING_ELAPSED])
        values.compact
      end

      def number(value)
        Float(value.to_s.strip, exception: false)
      end

      def file_value?(value) = value.to_s.strip.match?(FILE_PATTERN)

      def truthy?(value) = %w[true 1].include?(value.to_s.strip.downcase)

      def text(value)
        stripped = value.to_s.strip
        stripped.empty? ? nil : stripped
      end
    end
  end
end
