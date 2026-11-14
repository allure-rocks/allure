# frozen_string_literal: true

require "rails_helper"

# The operator site's environment reference (docs/site/README.md) must list
# every variable an operator can set, and nothing that no longer exists.
RSpec.describe "Operator documentation: environment reference" do
  let(:env_name) { /\A[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\z/ }

  # Read by tooling, not something an operator sets.
  let(:undocumented) { %w[BUNDLE_GEMFILE] }

  let(:root) { Rails.root }

  let(:documented) do
    root.join("docs/site/configuration/environment.md").read.scan(/^\| `([A-Z][A-Z0-9_]+)` \|/).flatten
  end

  # Development and test settings are not the operator's concern.
  let(:application_sources) do
    files = Dir[root.join("{app,lib,config}/**/*.{rb,erb,yml}")].reject do |path|
      path.include?("/lib/tasks/") || path.end_with?("config/environments/development.rb", "config/environments/test.rb")
    end
    files.map { File.read(it) }.select { it.match?(/\bENV\b/) }
  end

  let(:from_application) do
    application_sources.flat_map do |source|
      quoted = source.scan(/["']([A-Z][A-Z0-9_]+)["']/).flatten
      word_lists = source.scan(/%w\[([^\]]*)\]/).flatten.flat_map(&:split)
      (quoted + word_lists).grep(env_name)
    end
  end

  let(:from_route_renderer) do
    root.join("script/render-static-route").read.scan(/process\.env\.([A-Z][A-Z0-9_]+)/).flatten.grep(env_name)
  end

  let(:from_production_compose) do
    root.join("docker-compose.production.yml").read.scan(/\$\{([A-Z][A-Z0-9_]+)/).flatten
  end

  let(:from_production_example) do
    root.join("production.env.example").read.scan(/^#?\s*([A-Z][A-Z0-9_]+)=/).flatten
  end

  let(:used) do
    (from_application + from_route_renderer + from_production_compose + from_production_example).uniq - undocumented
  end

  it "documents every variable the application, the Compose file and the example read" do
    expect(used - documented).to be_empty
  end

  it "documents no variable that nothing reads" do
    expect(documented - used).to be_empty
  end

  it "documents each variable once" do
    expect(documented.tally.select { |_, count| count > 1 }.keys).to be_empty
  end

  # The Compose column tells operators where to set a variable: "env file" is
  # only true when the stock file passes it on from .env.production, and
  # "override" only when it does not mention it at all.
  describe "the Compose column" do
    let(:compose) { root.join("docker-compose.production.yml").read }
    let(:interpolated) { compose.scan(/\$\{([A-Z][A-Z0-9_]+)/).flatten.uniq }

    let(:column) do
      root.join("docs/site/configuration/environment.md").read
        .scan(/^\| `([A-Z][A-Z0-9_]+)` \|[^|]*\| ([a-z ()`]+?) \|/)
        .to_h { |name, value| [ name, value.split(" ").first ] }
    end

    it "says env file only for variables the stock file interpolates" do
      expect(column.select { |_, value| value == "env" }.keys - interpolated).to be_empty
    end

    it "says override only for variables the stock file never mentions" do
      overrides = column.select { |_, value| value == "override" }.keys

      expect(overrides.select { compose.match?(/\b#{it}\b/) }).to be_empty
    end

    it "gives every documented variable a known value" do
      expect(column.keys).to match_array(documented)
      expect(column.values.uniq - %w[env override fixed compose]).to be_empty
    end
  end
end
