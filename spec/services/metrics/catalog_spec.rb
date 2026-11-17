# frozen_string_literal: true

require "rails_helper"

# The exporter ↔ administration-console contract (docs/dev/METRICS.md). These
# guards fail when a metric lands without declaring which console concept it
# mirrors, when a mapping points at a label that no longer exists, or when an
# attachment owner appears without a storage translation.
RSpec.describe Metrics::Catalog do
  it "covers every declared gauge and nothing else" do
    declared = Metrics::Schema::GAUGES.map { |gauge| "allure_#{gauge[:name]}" }

    expect(described_class.gauges.map(&:family)).to match_array(declared)
  end

  it "covers every declared counter and nothing else" do
    declared = Metrics::Schema::COUNTERS.map { |counter| "allure_#{counter[:name]}" }

    expect(described_class.counters.map(&:family)).to match_array(declared)
  end

  it "covers every declared histogram and nothing else" do
    declared = Metrics::Schema::HISTOGRAMS.map { |histogram| "allure_#{histogram[:name]}" }

    expect(described_class.histograms.map(&:family)).to match_array(declared)
  end

  it "lists every exported family exactly once across its kinds" do
    families = described_class.entries.map(&:family)

    expect(families).to match_array(families.uniq)
  end

  it "maps every admin-facing family to an existing label" do
    described_class.gauges.filter_map(&:admin).each do |key|
      expect(I18n.exists?(key)).to be(true), "missing i18n key #{key}"
    end
  end

  it "labels every storage record type like the administration console" do
    keys = I18n.t("admin.dashboard.storage.record_types").keys.map(&:to_s)
    owners = ActiveStorage::Attachment.distinct.pluck(:record_type).map(&:underscore)

    expect(owners - keys).to be_empty
  end

  it "declares the yabeda-rails families separately from the gauges" do
    expect(described_class.gauges.map(&:family)).not_to include(a_string_starting_with("rails_"))
    expect(described_class::RAILS.map(&:kind).uniq).to match_array(%i[counter histogram])
  end

  it "only marks exported families as optional" do
    expect(described_class::OPTIONAL - described_class.entries.map(&:family)).to be_empty
  end
end
