# frozen_string_literal: true

module TcxFixtureHelpers
  def tcx_fixture_path(name) = Rails.root.join("spec/fixtures/tcx/#{name}.tcx")

  def parse_tcx_fixture(name, **options)
    Allure::Tcx::Parser.new(**options).parse(File.open(tcx_fixture_path(name)))
  end
end

RSpec.configure do |config|
  config.include TcxFixtureHelpers
end
