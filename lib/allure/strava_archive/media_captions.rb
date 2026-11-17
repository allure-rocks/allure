# frozen_string_literal: true

require "csv"

module Allure
  module StravaArchive
    # Reads `media.csv` (docs/dev/STRAVA-ARCHIVE.md): the archive's photo
    # names and their captions, in the athlete's language, so by position —
    # name first, caption second. The result maps `media/<name>` to the
    # caption, blank captions left out.
    module MediaCaptions
      module_function

      def parse(text)
        return {} if text.nil?

        rows = CSV.parse(text.to_s.dup.force_encoding(Encoding::UTF_8).scrub.delete_prefix("\uFEFF"))
        rows.drop(1).each_with_object({}) do |row, captions|
          name = row[0].to_s.strip[Activities::MEDIA_ITEM, 1]
          caption = row[1].to_s.strip
          captions["media/#{name}"] = caption if name && !caption.empty?
        end
      rescue CSV::MalformedCSVError
        {}
      end
    end
  end
end
