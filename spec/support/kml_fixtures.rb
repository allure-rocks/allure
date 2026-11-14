# frozen_string_literal: true

module KmlFixtureHelpers
  def kml_fixture_path(name) = Rails.root.join("spec/fixtures/kml/#{name}.kml")

  def parse_kml_fixture(name, **options)
    Allure::Kml::Parser.new(**options).parse(File.open(kml_fixture_path(name)))
  end
end

RSpec.configure do |config|
  config.include KmlFixtureHelpers
end
