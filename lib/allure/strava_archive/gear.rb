# frozen_string_literal: true

require "csv"

module Allure
  module StravaArchive
    # Reads `bikes.csv` and `shoes.csv` (docs/dev/STRAVA-ARCHIVE.md). The
    # English headers name the columns; a localized file is read by position,
    # name, brand and model first, as every known archive writes them. The
    # result is keyed by the name `activities.csv` uses for the gear,
    # case-insensitively: Strava names a nameless item « brand model » there.
    module Gear
      Item = Data.define(:name, :kind, :brand, :model) do
        def description = [ brand, model ].compact.join(" ").presence
      end

      COLUMNS = {
        bike: [ "Bike Name", "Bike Brand", "Bike Model" ],
        shoes: [ "Shoe Name", "Shoe Brand", "Shoe Model" ]
      }.freeze

      module_function

      # `files` maps :bike and :shoes to the CSV text (or nil when absent).
      def parse(files)
        files.each_with_object({}) do |(kind, text), result|
          next if text.nil?

          items(kind, text).each { |item| result[key(item.name)] ||= item }
        end
      end

      def key(name) = name.to_s.strip.downcase

      def items(kind, text)
        rows = CSV.parse(text.to_s.dup.force_encoding(Encoding::UTF_8).scrub.delete_prefix("\uFEFF"))
        header = rows.first || []
        indexes = COLUMNS.fetch(kind).each_with_index.map { |name, position| header.index(name) || position }
        rows.drop(1).filter_map do |row|
          name, brand, model = indexes.map { |index| row[index].to_s.strip.presence }
          # A nameless item is « brand model » in activities.csv.
          name ||= [ brand, model ].compact.join(" ").presence
          next unless name

          Item.new(name:, kind:, brand:, model:)
        end
      rescue CSV::MalformedCSVError
        []
      end
    end
  end
end
