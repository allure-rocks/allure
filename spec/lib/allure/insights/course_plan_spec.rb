# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §3.3: where the route is cut for the assistant, from the
# climbs and descents the laps already detected. Pure: no database, no clock.
RSpec.describe Allure::Insights::CoursePlan do
  def climb(start:, finish:, ascent: 100.0, name: nil, number: 1)
    { start_distance: start, end_distance: finish, ascent:, name:, number:, average_grade: 6.0 }
  end

  def descent(start:, finish:, descent: 100.0, number: 1)
    { start_distance: start, end_distance: finish, descent:, number:, average_grade: -6.0 }
  end

  let(:total) { 10_000.0 }

  describe "the terrain plan" do
    it "cuts around the one climb, with flat ground on both sides" do
      plan = described_class.terrain(total:, detected: { "climb" => [ climb(start: 4_000, finish: 6_000) ] })

      expect(plan.mode).to eq(:terrain)
      expect(plan.slots.map(&:terrain)).to eq(%w[between climb between])
      expect(plan.slots.map { [ it.start_distance, it.end_distance ] })
        .to eq([ [ 0.0, 4_000.0 ], [ 4_000.0, 6_000.0 ], [ 6_000.0, 10_000.0 ] ])
    end

    it "keeps a climb that covers the whole route" do
      plan = described_class.terrain(total:, detected: { "climb" => [ climb(start: 0, finish: 10_000) ] })

      expect(plan.slots.map(&:terrain)).to eq(%w[climb])
    end

    it "keeps the taller of two overlapping claims" do
      plan = described_class.terrain(total:, detected: {
        "climb" => [ climb(start: 2_000, finish: 6_000, ascent: 50) ],
        "descent" => [ descent(start: 3_000, finish: 5_000, descent: 300) ]
      })

      expect(plan.slots.map(&:terrain)).to eq(%w[between descent between])
      expect(plan.slots[1].start_distance).to eq(3_000.0)
    end

    it "absorbs a gap too short to deserve its own line" do
      plan = described_class.terrain(total:, detected: {
        "climb" => [ climb(start: 2_000, finish: 5_000), climb(start: 5_300, finish: 8_000, number: 2) ]
      })

      terrains = plan.slots.map(&:terrain)
      expect(terrains).to eq(%w[between climb climb between])
      expect(plan.slots[1].end_distance).to eq(5_300.0)
    end

    it "never leaves a hole between two sections" do
      plan = described_class.terrain(total:, detected: {
        "climb" => [ climb(start: 1_000, finish: 3_000) ],
        "descent" => [ descent(start: 7_000, finish: 9_000) ]
      })

      expect(plan.slots.first.start_distance).to eq(0.0)
      expect(plan.slots.last.end_distance).to eq(total)
      plan.slots.each_cons(2) { |first, second| expect(first.end_distance).to eq(second.start_distance) }
      expect(plan.boundaries).to eq([ 0.0, 1_000.0, 3_000.0, 7_000.0, 9_000.0, 10_000.0 ])
    end

    it "caps the table and keeps the biggest climb" do
      detected = { "climb" => 0.upto(11).map { |index| climb(start: index * 800.0, finish: (index * 800.0) + 600, number: index + 1, ascent: 10.0 + index) } }

      plan = described_class.terrain(total: 9_600.0, detected:)

      expect(plan.slots.length).to be <= Allure::Insights::CoursePlan::MAX_SECTIONS
      expect(plan.slots.map(&:height).max).to be >= 21.0
    end

    it "writes no terrain plan for a route too short to have sections" do
      expect(described_class.terrain(total: 2_000.0, detected: { "climb" => [ climb(start: 0, finish: 2_000) ] }))
        .to be_nil
    end

    it "writes no terrain plan without a detected climb or descent" do
      expect(described_class.terrain(total:, detected: {})).to be_nil
    end

    it "is deterministic" do
      detected = { "climb" => [ climb(start: 2_000, finish: 6_000) ],
                   "descent" => [ descent(start: 6_000, finish: 9_000) ] }

      first = described_class.terrain(total:, detected:)
      second = described_class.terrain(total:, detected:)

      expect(second.slots).to eq(first.slots)
    end
  end

  describe "the equal cut" do
    it "gives three parts to a short route" do
      plan = described_class.parts(total: 6_000)

      expect(plan.mode).to eq(:parts)
      expect(plan.slots.map(&:terrain)).to eq(%w[part part part])
      expect(plan.slots.map(&:end_distance)).to eq([ 2_000.0, 4_000.0, 6_000.0 ])
    end

    it "gives four parts to a long one" do
      plan = described_class.parts(total: 40_000)

      expect(plan.slots.length).to eq(4)
      expect(plan.slots.last.end_distance).to eq(40_000.0)
    end

    it "writes no plan for a route too short" do
      expect(described_class.parts(total: 2_500)).to be_nil
    end
  end
end
