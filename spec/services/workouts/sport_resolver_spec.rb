# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::SportResolver do
  let(:user) { create(:user) }
  let(:start) { Time.utc(2026, 5, 1, 8, 0, 0) }

  def track(**fit_options)
    parse_fit(build_fit(points: simple_fit_points(start:), **fit_options))
  end

  it "uses the file's own sport signal" do
    catalog_sport("cycling_road")
    catalog_sport("cycling")

    resolution = described_class.new(user:, track: track(sport: 2, sub_sport: 7)).call

    expect(resolution.sport.slug).to eq("cycling_road")
    expect(resolution.source).to eq("detected")
  end

  it "falls back to the platform sport when the file carries no usable sport" do
    rowing_virtual = catalog_sport("rowing_virtual")

    resolution = described_class.new(
      user:,
      track: track(manufacturer: 255, product: 22, serial_number: 1234)
    ).call

    expect(resolution.sport).to eq(rowing_virtual)
    expect(resolution.source).to eq("detected")
  end

  it "uses the caller's fallback when neither the file nor a platform resolves a sport" do
    cycling = catalog_sport("cycling")

    resolution = described_class.new(
      user:,
      track: track(manufacturer: 60_000),
      fallback_sport: cycling
    ).call

    expect(resolution.sport).to eq(cycling)
    expect(resolution.source).to eq("fallback")
  end

  it "raises when nothing resolves the sport" do
    expect { described_class.new(user:, track: track(manufacturer: 60_000)).call }
      .to raise_error(described_class::MissingSport)
  end

  describe "a declared sport (PLAN_STRAVA_ARCHIVE.md §4)" do
    it "outranks what the file detects" do
      trail = catalog_sport("trail")
      catalog_sport("cycling_road")

      resolution = described_class.new(user:, track: track(sport: 2, sub_sport: 7), declared_sport: trail).call

      expect(resolution.sport).to eq(trail)
      expect(resolution.source).to eq("declared")
    end

    it "lets the file refine a generic declaration to one of its variants" do
      road = catalog_sport("cycling_road")

      resolution = described_class.new(user:, track: track(sport: 2, sub_sport: 7),
                                       declared_sport: catalog_sport("cycling")).call

      expect(resolution.sport).to eq(road)
      expect(resolution.source).to eq("declared")
    end

    it "takes the account's default variant when the file says nothing more" do
      gravel = Sport.find_by!(slug: "cycling_gravel")
      user.update!(default_cycling_sport: gravel)

      resolution = described_class.new(user:, track: track(manufacturer: 60_000),
                                       declared_sport: catalog_sport("cycling")).call

      expect(resolution.sport).to eq(gravel)
    end

    it "keeps a positionless swim out of open water" do
      pool = Sport.find_by!(slug: "pool_swimming")
      points = simple_fit_points(start:).map { |point| point.merge(lat: nil, lon: nil, distance: 25.0) }
      positionless = parse_fit(build_fit(points:, manufacturer: 60_000))

      resolution = described_class.new(user:, track: positionless,
                                       declared_sport: Sport.find_by!(slug: "open_water_swimming")).call

      expect(resolution.sport).to eq(pool)
    end
  end

  # The file above carries no sport at all. `sport: 4` is not that file: a bare
  # `fitness_equipment` has an Allure equivalent since PLAN_NO_GPS.md §3.3
  # (`SportCatalog::SPORT_ALIASES`), and resolves like any other signal.
  it "resolves a bare fitness_equipment file to the indoor catch-all" do
    fitness = catalog_sport("fitness")

    resolution = described_class.new(user:, track: track(sport: 4, manufacturer: 60_000)).call

    expect(resolution.sport).to eq(fitness)
    expect(resolution.source).to eq("detected")
  end
end
