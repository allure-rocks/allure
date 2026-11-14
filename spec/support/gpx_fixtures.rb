# frozen_string_literal: true

module GpxFixtureHelpers
  def gpx_fixture_path(name) = Rails.root.join("spec/fixtures/gpx/#{name}.gpx")

  def parse_gpx_fixture(name, **options)
    Allure::Gpx::Parser.new(**options).parse(File.open(gpx_fixture_path(name)))
  end

  def analyze_gpx_fixture(name, stopped_speed_threshold_km_h: 0.5, records_elevation: true, elevation_filter: nil)
    track = parse_gpx_fixture(name)
    Allure::Gpx::Analyzer.new(
      stopped_speed_threshold_km_h:,
      records_elevation:,
      elevation_filter:
    ).analyze(track)
  end
end

RSpec.configure do |config|
  config.include GpxFixtureHelpers
end
