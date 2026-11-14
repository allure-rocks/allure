# frozen_string_literal: true

require_relative "manifests/full"
require_relative "manifests/minimal"

module DemoSeed
  # DEMO_DATASET names one of these, read by db/seeds/development.rb and
  # Demo::Reset alike: a manifest and the date anchors it is re-dated from.
  module Datasets
    Dataset = Data.define(:manifest, :anchors)

    def self.fetch(name)
      case name.to_s.strip.downcase
      when "full" then Dataset.new(manifest: Manifests::FULL, anchors: Manifests::DATE_ANCHORS)
      when "minimal" then Dataset.new(manifest: Manifests::MINIMAL, anchors: Manifests::MINIMAL_DATE_ANCHORS)
      else raise ArgumentError, "unknown DEMO_DATASET #{name.inspect}: use full or minimal"
      end
    end
  end
end
