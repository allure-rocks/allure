# frozen_string_literal: true

require "nokogiri"

module Allure
  module Federation
    module Privacy
      class SanitizedGpxBuilder
        class Unavailable < StandardError; end

        GPX_NAMESPACE = "http://www.topografix.com/GPX/1/1"

        def initialize(filtered:)
          @filtered = filtered
        end

        def call
          raise Unavailable, "sanitized route is unavailable" unless @filtered.usable?

          Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
            xml.gpx(version: "1.1", creator: "Allure", xmlns: GPX_NAMESPACE) do
              xml.trk do
                @filtered.segments.each do |segment|
                  xml.trkseg do
                    segment.each do |longitude, latitude|
                      xml.trkpt(lat: format_coordinate(latitude), lon: format_coordinate(longitude))
                    end
                  end
                end
              end
            end
          end.to_xml
        end

        private

        def format_coordinate(value) = format("%.7f", value)
      end
    end
  end
end
