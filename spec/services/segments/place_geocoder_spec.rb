# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::PlaceGeocoder do
  RecordingClient = Struct.new(:result, :calls) do
    def reverse(longitude:, latitude:, zoom:)
      calls << { longitude:, latitude:, zoom: }
      result
    end
  end

  let(:now) { Time.zone.parse("2026-10-12 10:00") }

  def client(result) = RecordingClient.new(result, [])

  def geocode(segment, result, **options)
    lookup = client(result)
    described_class.new(segment:, client: lookup, clock: -> { now }).call(**options)
    lookup
  end

  it "asks once at the course midpoint and keeps a recognizable feature" do
    segment = create(:segment)
    lookup = geocode(segment, { feature: { name: "Col du Test", kind: "pass" }, hierarchy: [ { name: "Vaujany", kind: "village" } ] })

    expect(lookup.calls.size).to eq(1)
    expect(lookup.calls.first[:longitude]).to be_within(1e-6).of(6.4083)
    expect(lookup.calls.first[:latitude]).to be_within(1e-6).of(45.0719)
    expect(lookup.calls.first[:zoom]).to eq(Allure::Toponyms::Nominatim::MARKER_ZOOM)
    expect(segment.reload).to have_attributes(place_name: "Col du Test", place_status: "ready", place_geocoded_at: now)
  end

  it "falls back from a road to the settlement around it" do
    segment = create(:segment)
    geocode(segment, { feature: { name: "Route du Col", kind: "route" },
                       hierarchy: [ { name: "Le Rivier", kind: "isolated_dwelling" }, { name: "Vaujany", kind: "village" } ] })

    expect(segment.reload.place_name).to eq("Vaujany")
  end

  it "marks an unmapped place unavailable" do
    segment = create(:segment)
    geocode(segment, nil)

    expect(segment.reload).to have_attributes(place_name: nil, place_status: "unavailable")
  end

  it "never geocodes a virtual course" do
    segment = create(:segment, sport: create(:sport, virtual: true))
    lookup = geocode(segment, { feature: { name: "Watopia", kind: "city" }, hierarchy: [] })

    expect(lookup.calls).to be_empty
    expect(segment.reload.place_status).to eq("unavailable")
  end

  it "keeps a settled place unless forced, and stays pending without a provider" do
    segment = create(:segment, place_status: "ready", place_name: "Rochelune")
    expect(geocode(segment, nil).calls).to be_empty

    geocode(segment, { feature: { name: "Jambes", kind: "suburb" }, hierarchy: [] }, force: true)
    expect(segment.reload.place_name).to eq("Jambes")

    pending = create(:segment)
    described_class.new(segment: pending, client: nil).call
    expect(pending.reload.place_status).to eq("pending")
  end
end
