# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::StravaArchive::Activities do
  let(:rows) do
    [
      { id: 101, name: "Col du Galibier", type: "Ride", description: "Line one\nline two", note: "Knee ok",
        commute: true, gear: "Canyon", filename: "activities/9001.fit.gz" },
      { id: 102, name: "Musculation", type: "Weight Training", filename: nil }
    ]
  end

  it "reads the leading columns of the current layout by position" do
    first, second = described_class.parse(strava_activities_csv(rows))

    expect(first).to have_attributes(
      id: "101", name: "Col du Galibier", type_label: "Ride", description: "Line one\nline two",
      private_note: "Knee ok", commute: true, gear_name: "Canyon", filename: "activities/9001.fit.gz",
      date: "Jun 1, 2026, 8:00:00 AM"
    )
    expect(first).to be_file
    expect(second).to have_attributes(id: "102", commute: false, gear_name: nil, filename: nil)
    expect(second).not_to be_file
  end

  it "reads the SI figures after the file column in both layouts" do
    [ false, true ].each do |legacy|
      second = described_class.parse(strava_activities_csv(rows, legacy:)).second

      expect(second.figures).to eq("elapsed" => 3600.0, "moving" => 3500.0, "distance" => 10_000.0)
    end
  end

  it "lists the photos of the last column, as media/ names only" do
    media = described_class.parse(strava_activities_csv([
      { id: 1, media: "media/a.jpg|b.png| media/a.jpg |../x.jpg|media/sub/c.jpg" }
    ])).first.media

    expect(media).to eq([ "media/a.jpg", "media/b.png" ])
  end

  it "keeps no more photos than a workout may hold" do
    names = Array.new(30) { |index| "media/#{index}.jpg" }

    media = described_class.parse(strava_activities_csv([ { id: 1, media: names.join("|") } ])).first.media

    expect(media).to eq(names.first(Allure::Photos::Config::MAX_PER_WORKOUT))
  end

  it "ignores the header language" do
    activities = described_class.parse(strava_activities_csv(rows, language: :de))

    expect(activities.map(&:filename)).to eq([ "activities/9001.fit.gz", nil ])
    expect(activities.first.gear_name).to eq("Canyon")
  end

  it "reads the legacy layout without the private note column" do
    first, = described_class.parse(strava_activities_csv(rows, legacy: true))

    expect(first).to have_attributes(private_note: nil, gear_name: "Canyon", filename: "activities/9001.fit.gz",
                                     commute: true)
  end

  it "keeps the current layout when no activity has a file" do
    activities = described_class.parse(strava_activities_csv([ rows.last ]))

    expect(activities.map(&:filename)).to eq([ nil ])
  end

  it "strips a byte order mark" do
    activities = described_class.parse("\uFEFF#{strava_activities_csv(rows)}")

    expect(activities.first.id).to eq("101")
  end

  it "refuses a file that is not an activities export" do
    expect { described_class.parse("Name,Brand\nCanyon,Canyon\n") }.to raise_error(described_class::MalformedError)
    expect { described_class.parse("") }.to raise_error(described_class::MalformedError)
  end

  it "refuses more activities than the cap" do
    stub_const("#{described_class}::MAX_ACTIVITIES", 1)

    expect { described_class.parse(strava_activities_csv(rows)) }.to raise_error(described_class::MalformedError)
  end
end
