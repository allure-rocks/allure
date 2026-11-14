# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::AcceptLanguage do
  let(:available) { %i[fr en de es nl] }

  def best(header) = described_class.best_match(header, available:)

  it "picks the most preferred offered language" do
    expect(best("de-DE,de;q=0.9,en;q=0.8")).to eq("de")
  end

  it "reaches a language through its regional variants" do
    expect(best("es-419")).to eq("es")
    expect(best("nl-BE")).to eq("nl")
    expect(best("fr-CA;q=0.7, it;q=0.9")).to eq("fr")
  end

  it "orders by weight before the header's own order" do
    expect(best("en;q=0.5, nl;q=0.8")).to eq("nl")
  end

  it "keeps the header's order between equal weights" do
    expect(best("es, de")).to eq("es")
  end

  it "skips languages that are not offered" do
    expect(best("it-IT,it;q=0.9,es;q=0.3")).to eq("es")
  end

  it "answers nil when nothing offered is accepted" do
    expect(best("it-IT,pt;q=0.9")).to be_nil
    expect(best(nil)).to be_nil
    expect(best("")).to be_nil
  end

  it "never chooses a refused language or the wildcard" do
    expect(best("de;q=0, *")).to be_nil
    expect(best("de;q=0.000")).to be_nil
  end

  it "ignores malformed ranges and weights" do
    expect(best("<script>, de;q=2, nl;q=abc, en;q=0.4")).to eq("en")
  end

  it "bounds the work on a hostile header" do
    header = "#{Array.new(10_000, 'xx').join(',')},de"

    expect(best(header)).to be_nil
    expect(best("de,#{'x' * 100_000}")).to eq("de")
  end

  it "is case-insensitive" do
    expect(best("DE-de")).to eq("de")
  end
end
