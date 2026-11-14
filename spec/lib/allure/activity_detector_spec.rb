# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::ActivityDetector do
  def track(name: nil, description: nil, creator: nil, signals: [])
    Allure::Gpx::Track.new(
      creator:,
      name:,
      description:,
      activity_signals: signals,
      segments: []
    )
  end

  def signal(source, value)
    Allure::Gpx::ActivitySignal.new(source:, value:)
  end

  it "maps explicit GPX and provider vocabulary to an Allure sport" do
    detection = described_class.new.detect(
      track(signals: [ signal(:gpx_track_type, "MountainBikeRide") ])
    )

    expect(detection).to have_attributes(
      sport_slug: "mountain_biking",
      source: :gpx_track_type,
      value: "MountainBikeRide",
      confidence: 100
    )
  end

  it "resolves TCX sport and KML name/description signals" do
    expect(described_class.new.detect(track(signals: [ signal(:tcx_sport, "run") ])))
      .to have_attributes(sport_slug: "running", source: :tcx_sport, confidence: 100)
    expect(described_class.new.detect(track(signals: [ signal(:kml_name, "Morning run") ])).sport_slug)
      .to eq("running")
    expect(described_class.new.detect(track(signals: [ signal(:kml_description, "easy run along the lake") ])).sport_slug)
      .to eq("running")
  end

  it "covers representative provider names and localized aliases" do
    expectations = {
      "AlpineSki" => "skiing_alpine",
      "EBikeRide" => "cycling_electric",
      "GravelRide" => "cycling_gravel",
      "Ride" => "cycling",
      "NordicSki" => "skiing_cross_country",
      "OpenWaterSwim" => "open_water_swimming",
      "StandUpPaddle" => "standup_paddleboarding",
      "VirtualRide" => "cycling_virtual",
      "Swimrun" => "swimrun",
      "Course à pied" => "running"
    }

    expectations.each do |value, sport_slug|
      expect(described_class.new.detect(track(signals: [ signal(:gpx_track_type, value) ])).sport_slug)
        .to eq(sport_slug), "expected #{value.inspect} to map to #{sport_slug.inspect}"
    end
  end

  it "normalizes accents and separators" do
    detection = described_class.new.detect(
      track(signals: [ signal(:osmand_activity, "Randonnée") ])
    )

    expect(detection.sport_slug).to eq("hiking")
  end

  it "prefers the longest matching phrase in track text" do
    detection = described_class.new.detect(track(name: "Saturday Trail Running"))

    expect(detection).to have_attributes(sport_slug: "trail", source: :track_name)
  end

  it "uses the fallback signal when explicit activity signals conflict" do
    detection = described_class.new.detect(
      track(signals: [
        signal(:gpx_track_type, "Running"),
        signal(:osmand_activity, "mountain_biking")
      ])
    )

    expect(detection).to be_nil
  end

  it "ignores a source name that does not identify an activity" do
    expect(described_class.new.detect(track(creator: "Strava"))).to be_nil
  end
end
