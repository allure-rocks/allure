# frozen_string_literal: true

require "rails_helper"

# The reference Grafana dashboard (docs/dev/METRICS.md) may only query families
# the exporter declares, so a renamed or removed metric fails here instead of
# leaving an empty panel in an operator's Grafana.
RSpec.describe "docs/grafana/allure.json" do
  let(:dashboard) { JSON.parse(Rails.root.join("docs/grafana/allure.json").read) }
  let(:expressions) do
    targets = dashboard.fetch("panels").flat_map { |panel| panel.fetch("targets", []) }
    annotations = dashboard.dig("annotations", "list").filter_map { |annotation| annotation["expr"] }
    targets.map { |target| target.fetch("expr") } + annotations
  end

  it "queries only exported families" do
    exported = Metrics::Catalog.entries.flat_map do |entry|
      entry.kind == :histogram ? %w[_bucket _sum _count].map { |suffix| entry.family + suffix } : [ entry.family ]
    end
    queried = expressions.flat_map { |expr| expr.scan(/\b(?:allure|rails)_[a-z0-9_]+/) }.uniq

    expect(queried - exported).to be_empty
  end

  it "reads every panel from the dashboard's datasource variable" do
    sources = dashboard.fetch("panels").reject { |panel| panel["type"] == "row" }.map { |panel| panel.dig("datasource", "uid") }

    expect(sources.uniq).to eq([ "${datasource}" ])
  end

  # Operators read it beside the English-only documentation (docs/site).
  it "is written in English" do
    texts = []
    collect = lambda do |node|
      case node
      when Hash
        node.each do |key, value|
          texts << value if %w[title description legendFormat displayName text name label].include?(key) && value.is_a?(String)
          collect.call(value)
        end
      when Array then node.each { collect.call(it) }
      end
    end
    collect.call(dashboard)

    expect(texts.grep(/[àâçéèêëîïôûùüœÀÂÇÉÈÊ«»]/)).to be_empty
  end

  it "has unique panel identifiers" do
    ids = dashboard.fetch("panels").map { |panel| panel.fetch("id") }

    expect(ids).to match_array(ids.uniq)
  end
end
