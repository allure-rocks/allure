# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Avatar::Generator do
  it "is a pure function of the seed" do
    expect(described_class.new(seed: 42).call).to eq(described_class.new(seed: 42).call)
  end

  it "varies across seeds" do
    recipes = (1..25).map { |seed| described_class.new(seed:).call }

    expect(recipes.uniq.length).to be > 1
  end

  it "draws the background from the curated palette and the shapes from the accents" do
    (1..40).each do |seed|
      recipe = described_class.new(seed:).call

      expect(Allure::Avatar::Palette::COLOURS).to include(recipe[:background])
      recipe[:shapes].each do |shape|
        fills = [ shape[:fill], shape[:stroke] ].compact - [ "none" ]
        expect(fills).to all(be_in(Allure::Avatar::Palette::ACCENTS))
      end
    end
  end

  it "emits only renderable shapes with bounded opacities" do
    (1..40).each do |seed|
      recipe = described_class.new(seed:).call

      expect(recipe[:shapes]).to be_present
      recipe[:shapes].each do |shape|
        expect(shape[:kind]).to be_in(%i[circle rect ellipse])
        expect(shape[:opacity]).to be_between(0.0, 1.0)
        expect(shape[:fill]).to be_present
      end
    end
  end
end
