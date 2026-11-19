# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Insights::Prompt do
  def fact(id, display, sentiment: :neutral, kind: "baseline", weight: 100)
    Allure::Insights::Fact.new(id:, kind:, display:, value: nil, unit: nil, direction: nil,
                               sentiment:, weight:, source: "workout")
  end

  let(:facts) do
    [
      fact("baseline:date", "17 novembre 2026"),
      fact("baseline:sport", "Vélo route"),
      fact("baseline:distance", "62,4 km"),
      fact("record:km10", "Meilleur temps sur 10 km : 41:32", sentiment: :good, kind: "record", weight: 92)
    ]
  end
  let(:prompt) { described_class.new(facts:, locale: "fr") }

  it "writes English instructions that name the member's language" do
    expect(prompt.system).to include("in French")
    expect(prompt.system).to include("Never invent a number")
    expect(prompt.system).to include("workout = activité")
    expect(prompt.system).to include("Never write a fact id in the text")
    expect(prompt.system).to include("Write exactly one sentence")
    expect(prompt.system).to include("exactly as its fact writes them")
    expect(prompt.system).to include("Rephrase the fact labels freely")
  end

  it "carries the voice of the interface, not the sober register" do
    expect(prompt.system).to include("a training partner texting right after the outing")
    expect(prompt.system).to include("The athlete is the subject")
    expect(prompt.system).to include("One exclamation mark at most")
    expect(prompt.system).to include("No emoji")
    expect(prompt.system).to include("never a unit")
    expect(prompt.system).to include('Address the owner as "vous"')
    expect(prompt.system).to include("one quiet sentence is the right answer")
    expect(prompt.system).to include("The course table describes the route in order")
    expect(prompt.system).not_to include("Sober register")
  end

  it "spells out the address form of the language" do
    german = described_class.new(facts:, locale: "de")

    expect(german.system).to include('Address the owner as "du"')
    expect(german.system).to include("verzeichnet")
  end

  it "gives a style example in the member's language, with no real place to copy" do
    expect(prompt.system).to include("Métronome dans la bosse")
    expect(prompt.system).to include("Boucle pépère")
    expect(prompt.system).to include("never reuse their places, numbers, wording or sentences")
    expect(prompt.system).not_to include("Chevreuse")
  end

  it "lends the sport's jargon only when the sport has a family" do
    cycling = described_class.new(facts:, locale: "fr", sport: "cycling_road")
    trail = described_class.new(facts:, locale: "fr", sport: "trail")
    tennis = described_class.new(facts:, locale: "fr", sport: "tennis_outdoor")

    expect(cycling.system).to include("Talk the way people who do this sport talk")
    expect(cycling.system).to include("D+, bosse, col")
    expect(trail.system).to include("glossary — D+, footing, fractionné")
    expect(tennis.system).not_to include("Talk the way people who do this sport talk")
  end

  it "asks one sentence when nothing is notable" do
    quiet = [ fact("baseline:date", "17 novembre 2026"),
              fact("place:route", "Par Chevreuse", kind: "place", weight: 45) ]

    prompt = described_class.new(facts: quiet, locale: "fr")

    expect(prompt.system).to include("Write exactly one sentence")
    expect(prompt.user).to include("Sentences: exactly 1.")
    expect(prompt.user).to include("Highlight this fact: place:route — Par Chevreuse")
  end

  it "tables the facts with their sentiment, after the sport and the date" do
    expect(prompt.user).to include("Sport: Vélo route. Date: 17 novembre 2026")
    expect(prompt.user).to include("baseline:distance | 62,4 km | neutral")
    expect(prompt.user).to include("record:km10 | Meilleur temps sur 10 km : 41:32 | good")
  end

  it "tables the course apart from the facts" do
    sections = [
      fact("section:1", "de 0,0 km à 4,2 km · plat · 5:05 /km", kind: "section", weight: 0),
      fact("section:2", "de 4,2 km à 9,8 km · montée « Col », 5,6 km à 6,0 %, 340 m", kind: "section", weight: 0)
    ]
    prompt = described_class.new(facts: facts + sections, locale: "fr")

    expect(prompt.user).to include("Course, in order from the start")
    expect(prompt.user).to include("section:2 | de 4,2 km à 9,8 km")
    expect(prompt.user.index("Facts (id | display | sentiment):")).to be < prompt.user.index("Course, in order")
    expect(prompt.user.scan(/^section:1 /).length).to eq(1)
  end

  it "writes no course block without sections" do
    expect(prompt.user).not_to include("Course, in order")
  end

  it "names the fact the summary opens with" do
    expect(prompt.user).to include("Highlight this fact: record:km10 — Meilleur temps sur 10 km : 41:32")
    expect(prompt.user).to include("Sentences: exactly 1.")
  end

  it "lets a story breathe when several facts carry it" do
    rich = facts + [
      fact("record:km5", "Meilleur temps sur 5 km : 19:40", sentiment: :good, kind: "record", weight: 82)
    ]
    prompt = described_class.new(facts: rich, locale: "fr")

    expect(prompt.system).to include("Write between 1 and 2 sentences")
    expect(prompt.user).to include("Sentences: 1 to 2.")
  end

  it "builds the two provider messages" do
    expect(prompt.messages).to eq(
      [ { role: "system", content: prompt.system }, { role: "user", content: prompt.user } ]
    )
  end
end
