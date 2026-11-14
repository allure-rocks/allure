# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::PersonalBestGaps do
  let(:user) { create(:user) }
  let(:running) { catalog_sport("running") }
  let(:segment) { create(:segment, user:, sport: nil, visibility: "public") }

  def effort(elapsed, started_at:, sport: running, owner: user, on: segment)
    workout = create(:workout, user: owner, sport:, started_at:)
    create(:segment_effort, segment: on, workout:, user: owner, sport:, elapsed_time: elapsed, started_at:)
  end

  it "gives a slower effort its gap to the record and the record its margin over the second best" do
    record = effort(100, started_at: 4.days.ago)
    second = effort(108, started_at: 3.days.ago)
    slow = effort(172, started_at: 2.days.ago)

    gaps = described_class.new(user:, efforts: [ record, second, slow ]).call

    expect(gaps).to eq(record.id => -8, second.id => 8, slow.id => 72)
  end

  it "gives a tied record a zero margin" do
    earlier = effort(120, started_at: 3.days.ago)
    later = effort(120, started_at: 1.day.ago)

    expect(described_class.new(user:, efforts: [ earlier, later ]).call).to eq(earlier.id => 0, later.id => 0)
  end

  it "has no gap for a first effort" do
    only = effort(150, started_at: 2.days.ago)

    expect(described_class.new(user:, efforts: [ only ]).call).to eq({})
  end

  it "never compares with another athlete, another sport or another segment" do
    mine = effort(150, started_at: 4.days.ago)
    effort(100, started_at: 3.days.ago, owner: create(:user))
    effort(100, started_at: 3.days.ago, sport: catalog_sport("cycling"))
    effort(100, started_at: 3.days.ago, on: create(:segment, user:, sport: nil))

    expect(described_class.new(user:, efforts: [ mine ]).call).to eq({})
  end
end
