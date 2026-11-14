# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::SportPalette do
  def seed_sport_rows
    seeds = Rails.root.join("db/seeds.rb").read
    rows = seeds[/sport_rows = \[(.*?)\]\.freeze/m, 1]
    rows.scan(/\[\s*"([^"]+)",\s*"[^"]+",\s*"([^"]+)"/).map { |slug, group| [ slug, group ] }
  end

  it "defines one family fallback partial for every icon family" do
    expect(described_class::FAMILY_PARTIALS.keys).to contain_exactly(*described_class::GROUPS)
  end

  it "gives every seeded sport its own partial" do
    seed_sport_rows.each do |slug, _group|
      expect(described_class.partial_for(slug)).to eq("sports/icons/#{slug}")
    end

    expect(described_class::PARTIALS.size).to eq(38)
  end

  # Colour is gone (DESIGN.md §6), so the glyph is the only at-a-glance
  # identifier beside the sport name: it must be unique across all sports.
  it "keeps icons globally distinct" do
    resolved = seed_sport_rows.map { |slug, group| described_class.icon_for(slug, group) }

    expect(resolved.uniq).to match_array(resolved)
    expect(resolved).to all(start_with("sports/icons/"))
  end

  it "ships every sport and family icon as an inline SVG partial" do
    paths = described_class::PARTIALS.values + described_class::FAMILY_PARTIALS.values

    paths.each do |partial|
      directory = File.dirname(partial)
      path = Rails.root.join("app/views/#{directory}/_#{File.basename(partial)}.html.erb")
      expect(path.exist?).to be(true), "expected #{path} to exist"
      svg = path.read
      # Every icon lives on the 1000×1000 grid and draws at the set's stroke
      # weight (DESIGN.md §6.4); a filled silhouette has no stroke to weigh.
      expect(svg).to match(/viewBox="0 0 1000 1000"/)
      expect(svg).to match(/stroke-width="(?:60|0)"/)
      expect(svg).to include('width="24"', 'height="24"', 'stroke="currentColor"',
                             'aria-hidden="true"')
      expect(svg).not_to include("style=", " id=")
    end
  end

  it "falls back to the family partial for an unknown slug" do
    expect(described_class.icon_for("nope", "ski")).to eq("sports/icons/families/ski")
    expect(described_class.icon_for("running", "run")).to eq("sports/icons/running")
    expect(described_class.partial_for("nope")).to be_nil
  end
end
