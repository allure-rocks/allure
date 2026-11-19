# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Insights::Verifier do
  def fact(id, display)
    Allure::Insights::Fact.new(id:, kind: "baseline", display:, value: nil, unit: nil, direction: nil,
                               sentiment: :neutral, weight: 100, source: "workout")
  end

  let(:facts) do
    [
      fact("baseline:distance", "62,4 km"),
      fact("baseline:ascent", "2 068 m"),
      fact("best_effort:km10", "Meilleur temps sur 10 km : 41:32")
    ]
  end
  let(:verifier) { described_class.new(facts) }

  def answer(sentences, title: "Le tour du lac")
    { "title" => title, "sentences" => sentences }
  end

  it "keeps a sentence whose numbers all come from the facts it cites" do
    result = verifier.call(answer([
      { "text" => "Vous avez parcouru 62,4 km et grimpé 2 068 m.",
        "fact_ids" => %w[baseline:distance baseline:ascent] },
      { "text" => "Votre meilleur 10 km reste à 41:32.", "fact_ids" => [ "best_effort:km10" ] }
    ]))

    expect(result).to be_valid
    expect(result.sentences.size).to eq(2)
    expect(result.title).to eq("Le tour du lac")
    expect(result).not_to be_dropped
  end

  it "accepts a single sentence as a complete answer" do
    result = verifier.call(answer([
      { "text" => "Une sortie sans histoire, au rythme du jour.", "fact_ids" => [ "baseline:distance" ] }
    ]))

    expect(result).to be_valid
    expect(result.sentences.size).to eq(1)
  end

  it "drops a sentence that invents a number" do
    result = verifier.call(answer([
      { "text" => "Vous avez parcouru 63,4 km.", "fact_ids" => [ "baseline:distance" ] },
      { "text" => "Votre meilleur 10 km reste à 41:32.", "fact_ids" => [ "best_effort:km10" ] }
    ]))

    expect(result.sentences.size).to eq(1)
    expect(result.refused_fact_ids).to eq([ "baseline:distance" ])
  end

  it "drops a sentence that takes a number from a fact it does not cite" do
    result = verifier.call(answer([
      { "text" => "Vous avez parcouru 62,4 km et grimpé 2 068 m.", "fact_ids" => [ "baseline:distance" ] },
      { "text" => "Votre meilleur 10 km reste à 41:32.", "fact_ids" => [ "best_effort:km10" ] }
    ]))

    expect(result.sentences.size).to eq(1)
    expect(result.refused_fact_ids).to eq([ "baseline:distance" ])
  end

  it "drops a sentence that writes a fact id in its text" do
    result = verifier.call(answer([
      { "text" => "La montée de baseline:distance a pris 62,4 km.", "fact_ids" => [ "baseline:distance" ] },
      { "text" => "Votre meilleur 10 km reste à 41:32.", "fact_ids" => [ "best_effort:km10" ] }
    ]))

    expect(result.sentences.size).to eq(1)
    expect(result.refused_fact_ids).to eq([ "baseline:distance" ])
  end

  it "drops a title that writes a fact id" do
    result = verifier.call(answer([
      { "text" => "Vous avez parcouru 62,4 km.", "fact_ids" => [ "baseline:distance" ] }
    ], title: "Le tour de baseline:distance"))

    expect(result.title).to be_nil
    expect(result.sentences.size).to eq(1)
  end

  it "drops a sentence citing an unknown fact" do
    result = verifier.call(answer([
      { "text" => "Vous avez parcouru 62,4 km.", "fact_ids" => [ "baseline:ghost" ] },
      { "text" => "Votre meilleur 10 km reste à 41:32.", "fact_ids" => [ "best_effort:km10" ] }
    ]))

    expect(result.sentences.size).to eq(1)
    expect(result.refused_fact_ids).to eq([ "baseline:ghost" ])
  end

  it "drops a title that uses a number no fact carries, and keeps the sentences" do
    result = verifier.call(answer([
      { "text" => "Vous avez parcouru 62,4 km.", "fact_ids" => [ "baseline:distance" ] },
      { "text" => "Votre meilleur 10 km reste à 41:32.", "fact_ids" => [ "best_effort:km10" ] }
    ], title: "Le tour du lac en 63 km"))

    expect(result.title).to be_nil
    expect(result.sentences.size).to eq(2)
  end

  it "is not valid with no surviving sentence" do
    result = verifier.call(answer([
      { "text" => "Vous avez parcouru 63,4 km.", "fact_ids" => [ "baseline:distance" ] },
      { "text" => "Votre meilleur 10 km reste à 99:99.", "fact_ids" => [ "best_effort:km10" ] }
    ]))

    expect(result).not_to be_valid
  end

  it "keeps no more sentences than the prompt asked for" do
    limited = described_class.new(facts, max_sentences: 1)
    result = limited.call(answer([
      { "text" => "Vous avez parcouru 62,4 km.", "fact_ids" => [ "baseline:distance" ] },
      { "text" => "Votre meilleur 10 km reste à 41:32.", "fact_ids" => [ "best_effort:km10" ] }
    ]))

    expect(result.sentences.size).to eq(1)
    expect(result).to be_valid
  end

  it "normalises thousands separators, decimals and units" do
    result = verifier.call(answer([
      { "text" => "2068 m de dénivelé et 62.4 km.", "fact_ids" => %w[baseline:ascent baseline:distance] },
      { "text" => "Votre meilleur 10 km reste à 41:32.", "fact_ids" => [ "best_effort:km10" ] }
    ]))

    expect(result.sentences.size).to eq(2)
  end

  it "accepts a sentence without any number" do
    result = verifier.call(answer([
      { "text" => "Une sortie de vélo sur route.", "fact_ids" => [ "baseline:distance" ] },
      { "text" => "Votre meilleur 10 km reste à 41:32.", "fact_ids" => [ "best_effort:km10" ] }
    ]))

    expect(result.sentences.size).to eq(2)
  end
end
