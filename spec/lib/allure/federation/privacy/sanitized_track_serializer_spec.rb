# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Federation::Privacy::SanitizedTrackSerializer do
  it "emits independent GeoJSON line features with no private point fields" do
    filtered = Allure::Federation::Privacy::ZoneFilter.new(
      segments: [ [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ], [ [ 6.6, 45.2 ], [ 6.7, 45.3 ] ] ],
      zones: []
    ).call

    result = described_class.new(filtered:).call

    expect(result).to eq(
      type: "FeatureCollection",
      features: [
        { type: "Feature", geometry: { type: "LineString", coordinates: [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] }, properties: { segment_index: 0 } },
        { type: "Feature", geometry: { type: "LineString", coordinates: [ [ 6.6, 45.2 ], [ 6.7, 45.3 ] ] }, properties: { segment_index: 1 } }
      ]
    )
    expect(result.to_s).not_to include("timestamp", "heart_rate", "private")
  end

  it "refuses to serialize a route with no usable visible run" do
    filtered = Allure::Federation::Privacy::FilteredTrack.new(
      segments: [], visible_points_count: 0, points_removed: true, interior_points_removed: false, bounds: nil, usable: false
    )

    expect { described_class.new(filtered:).call }
      .to raise_error(described_class::Unavailable)
  end
end
