# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Weather::NoteTags do
  let(:summary) do
    {
      "condition" => "showers", "temperature_min" => -2.0, "temperature_max" => 4.5, "temperature_mean" => 1.2,
      "apparent_temperature" => -6.1,
      "humidity" => 88, "precipitation" => 3.2, "wind_speed" => 7.4, "wind_gusts" => 15.0, "wind_direction" => 315,
      "wind_exposure" => { "head" => 0.5, "tail" => 0.25, "cross" => 0.25, "headwind" => 2.1 },
      "is_day" => false
    }
  end

  it "round-trips a summary through short SI tags" do
    tags = described_class.encode(summary)

    expect(tags.map(&:first)).to eq(described_class::NAMES)
    decoded = described_class.decode(tags.to_h)
    expect(decoded).to include("condition" => "showers", "temperature_min" => -2.0, "wind_direction" => 315.0,
                               "precipitation" => 3.2)
    expect(decoded["wind_exposure"]).to eq("head" => 0.5, "tail" => 0.25, "cross" => 0.25, "headwind" => 2.1)
  end

  it "keeps a partial summary and leaves empty positions absent" do
    decoded = described_class.decode({ "weather_temperature" => "8.0,12.0,", "weather_wind" => "3.0,,90" })

    expect(decoded).to eq("temperature_min" => 8.0, "temperature_max" => 12.0, "wind_speed" => 3.0,
                          "wind_direction" => 90.0)
  end

  it "drops malformed values and implausible summaries with a warning" do
    warnings = []
    warn = ->(message) { warnings << message }

    expect(described_class.decode({ "weather_condition" => "lava", "weather_humidity" => "abc" }, warn:)).to be_nil
    expect(described_class.decode({ "weather_temperature" => "20,10," }, warn:)).to be_nil
    expect(described_class.decode({ "weather_wind_exposure" => "0.9,0.9,0.9," }, warn:)).to be_nil
    expect(warnings).to include("invalid weather condition", "invalid weather value", "invalid weather summary")
  end

  it "encodes nothing for an invalid summary" do
    expect(described_class.encode(summary.merge("humidity" => 140))).to eq([])
    expect(described_class.encode(nil)).to eq([])
  end
end
