# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutAnomaliesHelper do
  let(:sport) { catalog_sport("cycling_road") }
  let(:details) do
    {
      "gps_rejected" => { "value" => 2, "count" => 2 },
      "gps_jump" => { "value" => 80.0, "speed" => 80.0, "metres" => 22 },
      "speed_implausible" => { "value" => 140.0, "speed" => 140.0, "ceiling" => 120 },
      "timestamp_skew" => { "value" => 83.1, "speed" => 83.1, "corrected" => 41.6, "count" => 2 },
      "recording_gap" => { "value" => 30, "seconds" => 30, "metres" => 240 },
      "hr_missing" => { "value" => 1585, "seconds" => 1585, "position" => "start" },
      "hr_frozen" => { "value" => 163, "bpm" => 163, "frozen" => 23, "missing" => 24 },
      "hr_jump" => { "value" => 39, "from" => 155, "to" => 116, "seconds" => 1 },
      "hr_out_of_range" => { "value" => 240, "bpm" => 240 },
      "elevation_step" => { "value" => -60.0, "metres" => -60.0, "seconds" => 1 },
      "elevation_mismatch" => { "value" => -14.8, "metres" => 14.8, "peak" => 25.7,
                                "first_distance" => 3258.6, "first_time" => 578, "count" => 15 },
      "power_spike" => { "value" => 2600, "reading" => 2600 },
      "cadence_spike" => { "value" => 255, "reading" => 255 }
    }
  end

  before { helper.define_singleton_method(:current_user) { nil } }

  it "describes every kind in both locales" do
    expect(details.keys).to match_array(Allure::Gpx::Anomalies::KINDS.keys)

    %i[fr en].each do |locale|
      I18n.with_locale(locale) do
        details.each do |kind, detail|
          expect(helper.anomaly_detail(kind, detail, sport:)).to be_present
          expect(I18n.t("workouts.anomalies.kinds.#{kind}")).to be_present
        end
      end
    end
  end

  it "names the repeat count and the converted speed" do
    I18n.with_locale(:fr) do
      text = helper.anomaly_detail("timestamp_skew", details["timestamp_skew"], sport:)

      expect(text).to include("83,1 km/h", "41,6 km/h", "×2")
    end
  end

  it "names the elevation gap and the passage it disagrees with" do
    I18n.with_locale(:fr) do
      text = helper.anomaly_detail("elevation_mismatch", details["elevation_mismatch"], sport:)

      expect(text).to include("15 m", "plus bas", "9:38")
    end
  end

  it "notes a contested ascent and the descent resting on the same readings" do
    workout = build(:workout, sport:, contested_metrics: %w[ascent], data_anomalies: {
      "impact" => { "ascent" => { "recorded" => 194, "gap" => 25.7,
                                  "start_distance" => 27_949.6, "end_distance" => 28_331.7 } }
    })

    I18n.with_locale(:fr) do
      notes = helper.workout_anomaly_notes(workout)

      expect(notes[:ascent][:text]).to include("26 m", "exclu des records")
      expect(notes[:descent][:text]).to include("26 m")
      expect(notes[:descent][:text]).not_to include("exclu des records")
      expect(notes[:ascent][:range]).to eq([ 27_949.6, 28_331.7 ])
      expect(helper.workout_anomaly_impacts(workout).map { |impact| impact[:key] }).to eq(%i[ascent descent])
    end
  end

  it "widens a one-point finding to a visible range" do
    expect(helper.anomaly_row_range({ start_distance: 0.0, end_distance: 0.0 })).to eq([ 0.0, 40.0 ])
    expect(helper.anomaly_row_range({ start_distance: 500.0, end_distance: 700.0 })).to eq([ 500.0, 700.0 ])
  end

  it "keeps only the position and timing findings for the map" do
    workout = build(:workout, sport:, data_anomalies: {
      "findings" => [
        { "kind" => "hr_jump", "start_distance" => 1.0, "end_distance" => 50.0, "start_time" => 1, "end_time" => 9,
          "detail" => details["hr_jump"] },
        { "kind" => "timestamp_skew", "start_distance" => 60.0, "end_distance" => 90.0, "start_time" => 10,
          "end_time" => 12, "detail" => details["timestamp_skew"] }
      ],
      "counts" => { "hr_jump" => 1, "timestamp_skew" => 1 }
    })

    anomalies = helper.workout_anomalies(workout)

    expect(helper.anomaly_map_payload(anomalies).map { |entry| entry["start"] }).to eq([ 60.0 ])
    expect(helper.anomaly_chart_payload(anomalies).length).to eq(2)
  end
end
