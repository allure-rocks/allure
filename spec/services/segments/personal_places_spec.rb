# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::PersonalPlaces do
  let(:user) { create(:user) }
  let(:running) { catalog_sport("running") }
  let(:segment) { create(:segment, user:, sport: nil, visibility: "public") }

  def effort(elapsed, started_at:, sport: running, owner: user, on: segment)
    workout = create(:workout, user: owner, sport:, started_at:)
    create(:segment_effort, segment: on, workout:, user: owner, sport:, elapsed_time: elapsed, started_at:)
  end

  it "places each effort among the athlete's own efforts on the same segment and sport" do
    fourth = effort(140, started_at: 5.days.ago)
    record = effort(100, started_at: 4.days.ago)
    third = effort(130, started_at: 3.days.ago)
    second = effort(120, started_at: 2.days.ago)

    places = described_class.new(user:, efforts: [ record, second, third, fourth ]).call

    expect(places).to eq(record.id => 1, second.id => 2, third.id => 3)
  end

  it "breaks ties on the earlier start" do
    later = effort(120, started_at: 1.day.ago)
    earlier = effort(120, started_at: 3.days.ago)

    expect(described_class.new(user:, efforts: [ later, earlier ]).call).to eq(earlier.id => 1, later.id => 2)
  end

  it "never counts another athlete, another sport or another segment" do
    mine = effort(150, started_at: 4.days.ago)
    effort(100, started_at: 3.days.ago, owner: create(:user))
    effort(100, started_at: 3.days.ago, sport: catalog_sport("cycling"))
    effort(100, started_at: 3.days.ago, on: create(:segment, user:, sport: nil))

    expect(described_class.new(user:, efforts: [ mine ]).call).to eq(mine.id => 1)
  end
end
