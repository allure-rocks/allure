# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Federation::Privacy::SanitizedPublicationBuilder do
  let(:settings) do
    {
      "title" => true,
      "description" => false,
      "metrics" => [ "distance" ],
      "route" => true,
      "gpx" => false,
      "route_image" => true,
      "mask_start" => true,
      "mask_finish" => true
    }
  end

  it "projects only profile-allowed values and never substitutes disabled media" do
    result = described_class.new(
      settings:,
      title: "Morning ride",
      description: "Private description",
      metrics: { "distance" => 250, "calories" => 600 },
      track: { type: "FeatureCollection" },
      gpx: "raw GPX must not be used",
      route_image: "sanitized image"
    ).call

    expect(result).to eq(
      title: "Morning ride",
      metrics: { "distance" => 250 },
      track: { type: "FeatureCollection" },
      route_image: "sanitized image"
    )
    expect(result).not_to have_key(:description)
    expect(result).not_to have_key(:gpx)
  end

  it "does not emit a disabled representation even when a value is provided" do
    result = described_class.new(
      settings: settings.merge("route" => false, "metrics" => []),
      title: "Title",
      description: "Description",
      metrics: { "distance" => 250 },
      track: { type: "FeatureCollection" },
      gpx: "sanitized GPX",
      route_image: "image"
    ).call

    expect(result).to eq(title: "Title", metrics: {}, route_image: "image")
  end

  it "rejects unknown settings instead of silently accepting a raw field" do
    expect do
      described_class.new(
        settings: { "coordinates" => true },
        title: nil,
        description: nil,
        metrics: {},
        track: nil,
        gpx: nil,
        route_image: nil
      )
    end.to raise_error(ArgumentError)
  end

  it "accepts independently disabled endpoint masking settings" do
    expect do
      described_class.new(
        settings: settings.merge("mask_start" => true, "mask_finish" => false),
        title: nil,
        description: nil,
        metrics: {},
        track: nil,
        gpx: nil,
        route_image: nil
      ).call
    end.not_to raise_error
  end

  it "shares the recording device only when the profile enables it" do
    result = described_class.new(
      settings: settings.merge("device" => true),
      title: nil,
      description: nil,
      metrics: {},
      track: nil,
      gpx: nil,
      route_image: nil,
      device: "Garmin Edge 530"
    ).call

    expect(result[:device]).to eq("Garmin Edge 530")
  end

  it "never emits the device while the setting is off or absent" do
    result = described_class.new(
      settings:,
      title: nil,
      description: nil,
      metrics: {},
      track: nil,
      gpx: nil,
      route_image: nil,
      device: "Garmin Edge 530"
    ).call

    expect(result).not_to have_key(:device)
  end

  it "bounds a long device string and drops a blank one" do
    bounded = described_class.new(
      settings: settings.merge("device" => true),
      title: nil,
      description: nil,
      metrics: {},
      track: nil,
      gpx: nil,
      route_image: nil,
      device: "x" * 400
    ).call
    blank = described_class.new(
      settings: settings.merge("device" => true),
      title: nil,
      description: nil,
      metrics: {},
      track: nil,
      gpx: nil,
      route_image: nil,
      device: "   "
    ).call

    expect(bounded[:device].length).to eq(described_class::MAX_DEVICE_LENGTH)
    expect(blank).not_to have_key(:device)
  end

  it "emits the commute flag only when the profile shares it and the workout is one" do
    base = { title: nil, description: nil, metrics: {}, track: nil, gpx: nil, route_image: nil }
    shared = described_class.new(**base, settings: settings.merge("commute" => true), commute: true).call
    not_commute = described_class.new(**base, settings: settings.merge("commute" => true), commute: false).call
    off = described_class.new(**base, settings:, commute: true).call

    expect(shared[:commute]).to be(true)
    expect(not_commute).not_to have_key(:commute)
    expect(off).not_to have_key(:commute)
  end

  it "carries only an explicitly closed thread, so an older profile keeps comments open" do
    base = { title: nil, description: nil, metrics: {}, track: nil, gpx: nil, route_image: nil }
    closed = described_class.new(**base, settings: settings.merge("comments" => false)).call
    open = described_class.new(**base, settings: settings.merge("comments" => true)).call
    older = described_class.new(**base, settings:).call

    expect(closed[:comments_closed]).to be(true)
    expect(open).not_to have_key(:comments_closed)
    expect(older).not_to have_key(:comments_closed)
  end
end
