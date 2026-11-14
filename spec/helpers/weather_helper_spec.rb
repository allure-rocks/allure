# frozen_string_literal: true

require "rails_helper"

RSpec.describe WeatherHelper, type: :helper do
  before { helper.define_singleton_method(:current_user) { nil } }

  it "writes a below-zero temperature with a true minus sign" do
    expect(helper.format_temperature(-5.4)).to eq("−5 °C")
    expect(helper.format_temperature(-0.3)).to eq("0 °C")
  end

  it "inlines one monochrome Meteocons icon per condition, day or night, with unique ids" do
    day = helper.weather_condition_icon("clear")
    night = helper.weather_condition_icon("clear", day: false)
    second = helper.weather_condition_icon("clear")

    expect(day).to include("allure-weather-icon", "clear-day")
    expect(night).to include("clear-night")
    expect(day).not_to eq(second)
    ids = [ day, second ].flat_map { |markup| markup.scan(/id="([^"]+)"/).flatten }
    expect(ids.uniq.length).to eq(ids.length)
    expect(helper.weather_condition_icon(nil)).to include("not-available")
  end

  it "draws in the theme's colour, never a colour of its own" do
    markup = helper.weather_condition_icon("partly_cloudy")

    expect(markup).to include("currentColor")
    expect(markup).not_to match(/(fill|stroke)="#/)
  end

  it "hands a marker both variants of its icon, for the controllers to draw" do
    svg = helper.weather_marker_svg("showers", day: false)

    expect(svg["animated"]).to include("partly-cloudy-night-rain", "<animate")
    expect(svg["static"]).to include("partly-cloudy-night-rain")
    expect(svg["static"]).not_to include("<animate")
  end

  it "pairs an animated icon with its static twin, and the static one alone on request" do
    animated = Nokogiri::HTML5.fragment(helper.weather_condition_icon("rain"))
    still = Nokogiri::HTML5.fragment(helper.weather_condition_icon("rain", animated: false))

    expect(animated.css(".allure-weather-icon--animated svg.allure-weather-icon__motion animateTransform")).to be_present
    expect(animated.css("svg.allure-weather-icon__still")).to be_present
    expect(still.css(".allure-weather-icon--animated, svg.allure-weather-icon__motion")).to be_empty
    expect(still.css("svg.allure-weather-icon__still animate, svg.allure-weather-icon__still animateTransform")).to be_empty
  end

  it "names every compass sector, north-west included (an unquoted NO is a YAML false)" do
    I18n.with_locale(:fr) do
      expect([ 0, 45, 90, 135, 180, 225, 270, 315 ].map { helper.wind_compass(it) })
        .to eq(%w[N NE E SE S SO O NO])
    end
  end

  it "joins a range with a dash between positive values and words once a bound is negative" do
    I18n.with_locale(:fr) do
      expect(helper.format_temperature_range(11.2, 15.8)).to eq("11–16 °C")
      expect(helper.format_temperature_range(-8.1, -5.2)).to eq("−8 à −5 °C")
      expect(helper.format_temperature_range(-2.0, 3.0)).to eq("−2 à 3 °C")
    end
    I18n.with_locale(:en) do
      expect(helper.format_temperature_range(-8.1, -5.2)).to eq("−8 to −5 °C")
    end
  end
end
