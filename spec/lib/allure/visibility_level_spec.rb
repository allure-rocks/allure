# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::VisibilityLevel do
  it "orders visibility from widest to narrowest" do
    expect(described_class::LEVELS).to eq(%w[public followers_only private])
  end

  it "caps every requested level at its parent" do
    described_class::LEVELS.each do |parent|
      described_class::LEVELS.each do |requested|
        expected_rank = [ described_class.rank(parent), described_class.rank(requested) ].max
        expect(described_class.rank(described_class.cap(requested, parent))).to eq(expected_rank)
      end
    end
  end

  it "rejects unknown visibility levels" do
    expect { described_class.rank("friends") }.to raise_error(ArgumentError)
  end
end
