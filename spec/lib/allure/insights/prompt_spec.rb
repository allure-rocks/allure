# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Insights::Prompt do
  def fact(id, display, kind: "baseline", weight: 100)
    Allure::Insights::Fact.new(id:, kind:, display:, value: nil, unit: nil, direction: nil,
                               sentiment: :neutral, weight:, source: "workout")
  end

  let(:facts) do
    [
      fact("baseline:date", "17 novembre 2026"),
      fact("baseline:sport", "Vélo route"),
      fact("baseline:distance", "62,4 km"),
      fact("record:km10", "Meilleur temps sur 10 km : 41:32", kind: "record", weight: 92),
      fact("company:with", "Avec Sophie", kind: "company", weight: 80)
    ]
  end
  let(:climb) { fact("climb:1", "Col du Galibier : 8,5 km à 6,8 %", kind: "climb", weight: 55) }
  let(:prompt) { described_class.new(facts:, locale: "fr") }

  it "writes English instructions that name the member's language" do
    expect(prompt.system).to include("in French")
    expect(prompt.system).to include("Never invent a number")
    expect(prompt.system).to include("workout = activité")
    expect(prompt.system).to include("Never write a fact id in the text")
    expect(prompt.system).to include("Write at most 3 sentences")
    expect(prompt.system).to include("exactly as its fact writes them")
    expect(prompt.system).to include("Rephrase the fact labels freely")
    expect(prompt.system).to include('"sentences"', '"fact_ids"')
  end

  it "carries the voice of the interface, not the sober register" do
    expect(prompt.system).to include("a training partner texting right after the outing")
    expect(prompt.system).to include("The athlete is the subject")
    expect(prompt.system).to include("One exclamation mark at most")
    expect(prompt.system).to include("No emoji")
    expect(prompt.system).to include("never a unit")
    expect(prompt.system).to include('Address the owner as "vous"')
    expect(prompt.system).to include("Most outings need one or two sentences")
    expect(prompt.system).to include("The course table describes the route in order")
  end

  it "describes the spoken rhythm instead of modelling a sentence" do
    expect(prompt.system).to include("Spoken rhythm")
    expect(prompt.system).to include("do not open two sentences the same way")
    expect(prompt.system).to include("One warm or wry remark at most")
    expect(prompt.system).not_to include("one idea each")
    expect(prompt.system).not_to include("you rode 204.6 km")
    expect(prompt.system).not_to include("you climbed the last hill")
  end

  it "leaves the choice of what the outing is about to the model" do
    expect(prompt.system).to include("Choose what this outing is about")
    expect(prompt.system).to include("Tell that one, and let the rest go")
    expect(prompt.system).to include("The facts marked as already on the page are rarely worth repeating")
    expect(prompt.system).not_to include("Start with the number or the action")
    expect(prompt.system).not_to include("Open with the highlighted fact")
  end

  it "shows no style example for the model to copy" do
    expect(prompt.system).not_to include("Métronome dans la bosse")
    expect(prompt.system).not_to include("Boucle pépère")
    expect(prompt.system).not_to include("Style examples")
  end

  it "offers the sport's vocabulary as one optional word, and only when it fits" do
    cycling = described_class.new(facts: facts + [ climb ], locale: "fr", sport: "cycling_road")
    flat = described_class.new(facts:, locale: "fr", sport: "cycling_road")
    tennis = described_class.new(facts:, locale: "fr", sport: "tennis_outdoor")

    expect(cycling.system).to include("If one word of the sport's own vocabulary fits naturally")
    expect(cycling.system).to include("bosse")
    expect(cycling.system).to include("most summaries need none")
    expect(flat.system).not_to include("col")
    expect(tennis.system).not_to include("If one word of the sport's own vocabulary fits naturally")
  end

  it "spells out the address form of the language" do
    german = described_class.new(facts:, locale: "de")

    expect(german.system).to include('Address the owner as "du"')
    expect(german.system).to include("verzeichnet")
  end

  it "groups the facts the page shows apart from the ones it does not" do
    expect(prompt.user).to include("Facts already shown on the workout page (rarely worth repeating):")
    expect(prompt.user).to include("Facts the page does not show:")
    expect(prompt.user.index("baseline:distance")).to be < prompt.user.index("Facts the page does not show:")
    expect(prompt.user.index("record:km10")).to be > prompt.user.index("Facts the page does not show:")
    expect(prompt.user).to include("record:km10 | Meilleur temps sur 10 km : 41:32")
    expect(prompt.user).not_to include("| neutral")
  end

  it "orders the unshown facts by theme, never by weight" do
    expect(prompt.user.index("record:km10")).to be < prompt.user.index("company:with")
  end

  it "imposes no opening fact" do
    expect(prompt.user).not_to include("Highlight this fact")
  end

  it "bounds the answer to three sentences without turning the bound into a target" do
    quiet = [ fact("baseline:date", "17 novembre 2026"),
              fact("place:route", "Par Chevreuse", kind: "place", weight: 45) ]
    single = described_class.new(facts: quiet, locale: "fr")
    rich = described_class.new(facts: facts + [
      fact("record:km5", "Meilleur temps sur 5 km : 19:40", kind: "record", weight: 82),
      fact("weather:conditions", "Pluie, 4 à 8 °C", kind: "weather", weight: 50)
    ], locale: "fr")

    expect(single.sentence_range).to eq(1..3)
    expect(rich.sentence_range).to eq(1..3)
    expect(single.user).to include("Sentences: usually one or two, 3 at most.")
    expect(single.system).to include("Most outings need one or two sentences")
  end

  it "tables the course apart from the facts" do
    sections = [
      fact("section:1", "de 0,0 km à 4,2 km · plat · 5:05 /km", kind: "section", weight: 0),
      fact("section:2", "de 4,2 km à 9,8 km · montée « Col », 5,6 km à 6,0 %, 340 m", kind: "section", weight: 0)
    ]
    prompt = described_class.new(facts: facts + sections, locale: "fr")

    expect(prompt.user).to include("Course, in order from the start")
    expect(prompt.user).to include("section:2 | de 4,2 km à 9,8 km")
    expect(prompt.user.index("Facts the page does not show:")).to be < prompt.user.index("Course, in order")
    expect(prompt.user.scan(/^section:1 /).length).to eq(1)
  end

  it "writes no course block without sections" do
    expect(prompt.user).not_to include("Course, in order")
  end

  it "offers a place or a person from the facts for the title" do
    expect(prompt.system).to include("a place, a person or a detail from the facts makes a good one")
  end

  it "builds the two provider messages" do
    expect(prompt.messages).to eq(
      [ { role: "system", content: prompt.system }, { role: "user", content: prompt.user } ]
    )
  end
end
