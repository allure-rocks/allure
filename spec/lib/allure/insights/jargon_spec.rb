# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §4.1 and DESIGN.md §4: the summary may borrow a sport's own
# vocabulary. The families are curated here, not read from the icon groups,
# and every listed sport must exist in the seeded catalog.
RSpec.describe Allure::Insights::Jargon do
  described_class::FAMILIES.each do |family, slugs|
    describe "the #{family} family" do
      it "maps its sports back to it" do
        expect(slugs.map { described_class.family(it) }.uniq).to eq([ family ])
      end

      it "has words in every locale" do
        described_class::WORDS.each_value do |locales|
          expect(locales[family]).to be_present
        end
      end

      it "lists no number and no unit" do
        words = described_class::WORDS.values.flat_map { it.fetch(family) }

        expect(words.join(" ")).not_to match(/\d/)
        expect(words).not_to include("km", "mi", "m")
      end
    end
  end

  it "lists only sports of the seeded catalog" do
    seeded = Sport.pluck(:slug)
    listed = described_class::FAMILIES.values.flatten

    expect(seeded).to include(*listed)
  end

  it "leaves the sports without a family alone" do
    expect(described_class.family("tennis_outdoor")).to be_nil
    expect(described_class.words("tennis_outdoor", locale: :fr)).to be_nil
  end

  it "answers a family's words in the member's language" do
    expect(described_class.words("cycling_road", locale: :fr)).to include("bosse")
    expect(described_class.words("trail", locale: :fr)).to include("fractionné")
    expect(described_class.words("cycling_road", locale: :nl)).to include("klim")
  end

  it "falls back to English for an unknown locale" do
    expect(described_class.words("cycling_road", locale: :it)).to eq(described_class.words("cycling_road", locale: :en))
  end
end
