# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §4.1: the sport's vocabulary is an offer, one word at most,
# and a climb word only on an outing that climbed.
RSpec.describe Allure::Insights::Jargon do
  it "groups the sports by the way people talk about them" do
    expect(described_class.family("cycling_gravel")).to eq("cycling")
    expect(described_class.family("trail")).to eq("running")
    expect(described_class.family("snowshoes")).to eq("hiking")
    expect(described_class.family("tennis_outdoor")).to be_nil
  end

  it "offers at most three words, and the climb words only when the outing climbed" do
    climbing = described_class.words("cycling_road", locale: :fr, climbing: true)
    flat = described_class.words("cycling_road", locale: :fr, climbing: false)

    expect(climbing.size).to be <= described_class::WORD_LIMIT
    expect(climbing).to include("bosse")
    expect(flat).not_to include("bosse", "col")
    expect(flat).to include("mouliner")
  end

  it "gives no vocabulary to a sport with no family" do
    expect(described_class.words("tennis_outdoor", locale: :fr, climbing: true)).to be_nil
  end

  it "speaks the member's language, falling back to English" do
    expect(described_class.words("running", locale: :de, climbing: true)).to include("Steigung")
    expect(described_class.words("running", locale: :it, climbing: true)).to include("hills")
  end

  it "never offers a word that carries a number or a unit" do
    %i[fr en de es nl].each do |locale|
      words = described_class::WORDS.fetch(locale).values.flat_map { |entries| entries[:general] + entries[:climb] }

      expect(words).to all(match(/\A[[:alpha:] ]+\z/))
    end
  end
end
