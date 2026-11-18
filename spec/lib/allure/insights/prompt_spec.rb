# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Insights::Prompt do
  def fact(id, display, sentiment: :neutral)
    Allure::Insights::Fact.new(id:, kind: "baseline", display:, value: nil, unit: nil, direction: nil,
                               sentiment:, weight: 100, source: "workout")
  end

  let(:facts) do
    [
      fact("baseline:date", "17 novembre 2026"),
      fact("baseline:sport", "Vélo route"),
      fact("baseline:distance", "62,4 km"),
      fact("record:km10", "Meilleur temps sur 10 km : 41:32", sentiment: :good)
    ]
  end
  let(:prompt) { described_class.new(facts:, locale: "fr") }

  it "writes English instructions that name the member's language" do
    expect(prompt.system).to include("in French")
    expect(prompt.system).to include("Never invent a number")
    expect(prompt.system).to include("workout = activité")
    expect(prompt.system).to include("Never write a fact id in the text")
    expect(prompt.system).to include("Two to five sentences")
    expect(prompt.system).to include("exactly as its fact writes it")
  end

  it "tables the facts with their sentiment, after the sport and the date" do
    expect(prompt.user).to include("Sport: Vélo route. Date: 17 novembre 2026")
    expect(prompt.user).to include("baseline:distance | 62,4 km | neutral")
    expect(prompt.user).to include("record:km10 | Meilleur temps sur 10 km : 41:32 | good")
  end

  it "builds the two provider messages" do
    expect(prompt.messages).to eq(
      [ { role: "system", content: prompt.system }, { role: "user", content: prompt.user } ]
    )
  end
end
