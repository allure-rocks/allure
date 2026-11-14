# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Federation::Privacy::SanitizedGpxBuilder do
  it "builds valid multi-segment GPX without timestamps or sensor extensions" do
    filtered = Allure::Federation::Privacy::ZoneFilter.new(
      segments: [ [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ], [ [ 6.6, 45.2 ], [ 6.7, 45.3 ] ] ],
      zones: []
    ).call

    document = Nokogiri::XML(described_class.new(filtered:).call)
    document.remove_namespaces!

    expect(document.errors).to be_empty
    expect(document.xpath("/gpx/trk/trkseg").length).to eq(2)
    expect(document.xpath("//trkpt").map { |point| [ point["lon"].to_f, point["lat"].to_f ] }).to eq([
      [ 6.4, 45.0 ], [ 6.5, 45.1 ], [ 6.6, 45.2 ], [ 6.7, 45.3 ]
    ])
    expect(document.xpath("//time | //ele | //extensions")).to be_empty
  end

  it "refuses to build an empty sanitized route" do
    filtered = Allure::Federation::Privacy::FilteredTrack.new(
      segments: [], visible_points_count: 0, points_removed: true, interior_points_removed: false, bounds: nil, usable: false
    )

    expect { described_class.new(filtered:).call }
      .to raise_error(described_class::Unavailable)
  end
end
