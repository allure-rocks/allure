# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Photos::Placement do
  let(:start) { Time.utc(2026, 5, 1, 8) }
  # Two segments heading north along one meridian, ~111 m per 0.001°, with a
  # ten-minute pause between them.
  let(:segments) do
    [
      { started_at: start, points: [
        { "t" => 0, "d" => 0.0, "lon" => 6.0, "lat" => 45.000 },
        { "t" => 100, "d" => 111.2, "lon" => 6.0, "lat" => 45.001 }
      ] },
      { started_at: start + 700, points: [
        { "t" => 0, "d" => 111.2, "lon" => 6.0, "lat" => 45.002 },
        { "t" => 100, "d" => 222.4, "lon" => 6.0, "lat" => 45.003 }
      ] }
    ]
  end
  subject(:placement) { described_class.new(segments:, started_at: start) }

  it "keeps a nearby EXIF position and measures where it falls along the route" do
    result = placement.automatic(exif_longitude: 6.0003, exif_latitude: 45.0005)

    expect(result.source).to eq("exif")
    expect([ result.longitude, result.latitude ]).to eq([ 6.0003, 45.0005 ])
    expect(result.distance).to be_within(1).of(55.6)
    expect(result.elapsed).to be_within(1).of(50)
  end

  it "ignores an EXIF position far from the route and uses the capture time" do
    result = placement.automatic(exif_longitude: 6.1, exif_latitude: 45.0, taken_at: start + 50)

    expect(result.source).to eq("time")
    expect(result.latitude).to be_within(1e-7).of(45.0005)
    expect(result.distance).to be_within(0.1).of(55.6)
  end

  it "places a photo taken during a pause where the previous segment ended" do
    result = placement.at_time(start + 400)

    expect([ result.longitude, result.latitude ]).to eq([ 6.0, 45.001 ])
    expect(result.elapsed).to eq(400)
  end

  it "accepts five minutes either side and refuses beyond" do
    expect(placement.at_time(start - 299).latitude).to eq(45.0)
    expect(placement.at_time(start + 800 + 299).latitude).to eq(45.003)
    expect(placement.at_time(start - 301)).to be_nil
    expect(placement.at_time(start + 800 + 301)).to be_nil
  end

  it "snaps the owner's click onto the line and refuses a far one" do
    result = placement.snap(6.0005, 45.0025)

    expect(result.source).to eq("manual")
    expect([ result.longitude, result.latitude ]).to eq([ 6.0, 45.0025 ])
    expect(result.distance).to be_within(0.5).of(166.8)
    expect(placement.snap(6.5, 45.0)).to be_nil
  end

  it "has nothing to place against without coordinates" do
    empty = described_class.new(segments: [ { started_at: start, points: [ { "t" => 0, "d" => 0.0 } ] } ], started_at: start)

    expect(empty).not_to be_positioned
    expect(empty.automatic(taken_at: start)).to be_nil
  end

  describe "#diagnose" do
    it "names an EXIF position too far from the route" do
      diagnosis = placement.diagnose(exif_longitude: 6.1, exif_latitude: 45.0)

      expect(diagnosis.exif_metres).to be > 200
      expect(diagnosis.before_start).to be_nil
      expect(diagnosis.after_finish).to be_nil
    end

    it "names a capture time before the start and after the finish" do
      before = placement.diagnose(taken_at: start - 400)
      after = placement.diagnose(taken_at: start + 800 + 400)

      expect(before.before_start).to eq(400)
      expect(before.after_finish).to be_nil
      expect(after.after_finish).to eq(400)
      expect(after.before_start).to be_nil
    end

    it "has no diagnosis when the clues place the photo" do
      expect(placement.diagnose(exif_longitude: 6.0003, exif_latitude: 45.0005, taken_at: start + 50)).to be_nil
      expect(placement.diagnose(taken_at: start + 50)).to be_nil
    end

    it "has no diagnosis without a clue" do
      expect(placement.diagnose).to be_nil
    end
  end
end
