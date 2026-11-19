# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §3.5: the facts' values use the same units and number rules as
# the interface, in every locale. The helper is the reference.
RSpec.describe Allure::Insights::Format do
  def rendered(source, locale:)
    I18n.with_locale(locale) { ApplicationController.renderer.render(inline: source) }.strip
  end

  def format_for(locale, unit_system)
    described_class.new(locale:, unit_system:)
  end

  [ [ :fr, "metric" ], [ :en, "metric" ], [ :de, "imperial" ], [ :es, "imperial" ], [ :nl, "metric" ] ].each do |locale, units|
    it "matches WorkoutsHelper in #{locale} (#{units})" do
      format = format_for(locale, units)
      source = <<~ERB
        <%= format_distance(6123.4, unit_system: "#{units}", precision: 1) %>|<%= format_distance(612.0, unit_system: "#{units}") %>|<%= format_elevation(850.4, unit_system: "#{units}") %>|<%= format_speed(7.4938, unit_system: "#{units}") %>|<%= format_pace(133, unit_system: "#{units}") %>|<%= format_duration_human(9660) %>|<%= format_grade(4.64) %>
      ERB
      expected = [
        format.distance(6_123.4, precision: 1), format.distance(612.0), format.elevation(850.4),
        format.speed(7.4938), format.pace(133), format.duration_human(9_660), format.grade(4.64)
      ].join("|")

      expect(rendered(source, locale:)).to eq(expected)
    end
  end

  it "matches WeatherHelper for temperatures" do
    format = format_for(:fr, "metric")
    source = <<~ERB
      <%= format_temperature(11.7, unit_system: "metric") %>|<%= format_temperature_range(7.7, 15.5, unit_system: "metric") %>|<%= format_temperature_range(-8.2, -5.4, unit_system: "metric") %>
    ERB
    expected = [
      format.temperature(11.7), format.temperature_range(7.7, 15.5), format.temperature_range(-8.2, -5.4)
    ].join("|")

    expect(rendered(source, locale: :fr)).to eq(expected)
  end

  it "renders a fixed pace basis whatever the unit system" do
    format = format_for(:en, "imperial")
    rendered_value = rendered(
      "<%= format_pace(120, unit_system: 'imperial', sport: Sport.new(pace_basis_metres: 500)) %>", locale: :en
    )

    expect(format.pace(60, basis: 500)).to eq(rendered_value)
    expect(rendered_value).to include("500m")
  end

  it "renders a signed delta like the helper" do
    format = format_for(:fr, "metric")

    expect(format.duration_delta(72)).to eq("+1:12")
    expect(format.duration_delta(-18)).to eq("−18 s")
    expect(format.duration(9_660)).to eq("2:41:00")
    expect(format.duration(372)).to eq("6:12")
  end

  it "writes a pace delta as a duration, never as a clock time" do
    format = format_for(:fr, "metric")

    expect(format.pace_delta(33)).to eq("33 s /km")
    expect(format.pace_delta(96)).to eq("1 min 36 s /km")
    expect(format.pace_delta(120)).to eq("2 min /km")
    expect(format.pace_delta(96, basis: 500)).to eq("1 min 36 s /500m")
  end

  it "writes the local date in the member's language" do
    time = Time.iso8601("2026-11-17T09:00:00+01:00")

    expect(format_for(:fr, "metric").date(time)).to eq("17 novembre 2026")
    expect(format_for(:en, "metric").date(time)).to eq("November 17, 2026")
  end
end
