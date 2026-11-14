# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Stats::TrainingLoad do
  let(:start) { Date.new(2026, 10, 1) }

  it "starts at zero and averages the daily load over 42 and 7 days" do
    model = described_class.new({ start => 84.0 }, through: start + 1)

    first, second = model.days
    expect(first).to have_attributes(date: start, load: 84.0, fitness: 2.0, fatigue: 12.0, form: 0.0)
    expect(second.load).to eq(0.0)
    expect(second.form).to eq(-10.0)
    expect(second.fitness).to be_within(1e-9).of(2.0 - (2.0 / 42))
    expect(second.fatigue).to be_within(1e-9).of(12.0 - (12.0 / 7))
  end

  it "fills quiet days so the decay reaches today" do
    model = described_class.new({ start => 50.0, start + 3 => 20.0 }, through: start + 10)

    expect(model.days.map(&:date)).to eq((start..(start + 10)).to_a)
    expect(model.today.date).to eq(start + 10)
    expect(model.last(3).size).to eq(3)
  end

  it "converges to a steady load" do
    loads = (0...400).to_h { [ start + it, 60.0 ] }
    model = described_class.new(loads, through: start + 399)

    expect(model.today.fitness).to be_within(0.1).of(60.0)
    expect(model.today.fatigue).to be_within(0.1).of(60.0)
    expect(model.today.form).to be_within(0.1).of(0.0)
  end

  it "is empty without a load" do
    expect(described_class.new({}, through: start)).to be_empty
  end
end
