# frozen_string_literal: true

require "rails_helper"

# M0.4 exit criterion.
#
# This is not a "does the extension exist" check. It proves the whole chain that
# M1 depends on: the postgis adapter is active, geography columns survive a
# round-trip through ActiveRecord as RGeo objects, GEOS-backed measurement works,
# and geometry converts to the GeoJSON that both our maps and the Wanderer
# federation payloads need.
RSpec.describe "PostGIS integration" do
  connection = ActiveRecord::Base.connection

  # A representative fragment of a real track: four points climbing the west
  # side of the Col du Galibier.
  TRACK = [
    [ 6.4074, 45.0710 ],
    [ 6.4092, 45.0728 ],
    [ 6.4110, 45.0745 ],
    [ 6.4131, 45.0761 ]
  ].freeze

  before(:all) do
    connection.execute(<<~SQL)
      CREATE TEMPORARY TABLE spatial_smoke_tests (
        id           bigserial PRIMARY KEY,
        start_point  geography(Point, 4326),
        track        geography(LineString, 4326)
      )
    SQL
  end

  after(:all) do
    connection.execute("DROP TABLE IF EXISTS spatial_smoke_tests")
  end

  let(:model) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "spatial_smoke_tests"
      def self.name = "SpatialSmokeTest"
    end
  end

  let(:factory) { RGeo::Geographic.spherical_factory(srid: 4326) }
  let(:point) { factory.point(*TRACK.first) }
  let(:line) { factory.line_string(TRACK.map { |lon, lat| factory.point(lon, lat) }) }

  it "uses the PostGIS adapter" do
    expect(connection.adapter_name).to eq("PostGIS")
  end

  it "reports GEOS and PROJ support" do
    expect(connection.select_value("SELECT postgis_version()")).to include("USE_GEOS=1", "USE_PROJ=1")
  end

  it "round-trips a geography(Point, 4326) as an RGeo point" do
    record = model.create!(start_point: point)
    reloaded = model.find(record.id)

    expect(reloaded.start_point).to be_a(RGeo::Feature::Point)
    expect(reloaded.start_point.srid).to eq(4326)
    expect(reloaded.start_point.x).to be_within(1e-6).of(6.4074)
    expect(reloaded.start_point.y).to be_within(1e-6).of(45.0710)
  end

  it "round-trips a geography(LineString, 4326) preserving every vertex" do
    record = model.create!(track: line)
    reloaded = model.find(record.id)

    expect(reloaded.track).to be_a(RGeo::Feature::LineString)
    expect(reloaded.track.num_points).to eq(TRACK.length)
    expect(reloaded.track.points.map { [ _1.x.round(4), _1.y.round(4) ] })
      .to eq(TRACK.map { |lon, lat| [ lon.round(4), lat.round(4) ] })
  end

  it "measures true geodesic length in metres" do
    record = model.create!(track: line)

    # Cross-check by hand: at latitude 45, 1° of longitude is ~78.7 km and 1° of
    # latitude ~111.1 km, so Δlon 0.0057° ≈ 448 m and Δlat 0.0051° ≈ 567 m,
    # giving a hypotenuse of ~722 m.
    #
    # Geography (not geometry) means the answer comes back in metres with no
    # projection juggling. That is precisely why these columns are geography,
    # and it underpins every distance metric in M1.
    metres = model.where(id: record.id).pick(Arel.sql("ST_Length(track)"))
    expect(metres).to be_within(15).of(724)
  end

  it "supports spatial predicates used by proximity search" do
    record = model.create!(start_point: point)

    near = model.where(id: record.id)
                .pick(Arel.sql("ST_DWithin(start_point, ST_MakePoint(6.4074, 45.0710)::geography, 50)"))
    far = model.where(id: record.id)
               .pick(Arel.sql("ST_DWithin(start_point, ST_MakePoint(2.3522, 48.8566)::geography, 50)"))

    expect(near).to be(true)
    expect(far).to be(false)
  end

  it "converts geometry to GeoJSON for maps and federation payloads" do
    record = model.create!(track: line)
    reloaded = model.find(record.id)

    geojson = RGeo::GeoJSON.encode(reloaded.track)

    expect(geojson["type"]).to eq("LineString")
    expect(geojson["coordinates"].length).to eq(TRACK.length)
    expect(geojson["coordinates"].first.map { _1.round(4) }).to eq([ 6.4074, 45.0710 ])
  end

  it "parses GeoJSON back into geometry, as inbound federation will" do
    payload = {
      "type" => "LineString",
      "coordinates" => TRACK
    }

    parsed = RGeo::GeoJSON.decode(payload, geo_factory: factory)

    expect(parsed).to be_a(RGeo::Feature::LineString)
    expect(parsed.num_points).to eq(TRACK.length)
  end
end
