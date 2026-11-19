# frozen_string_literal: true

require "rails_helper"

RSpec.describe Metrics::QueueName do
  it "keeps the documented queues and folds everything else into other" do
    expect(described_class::KNOWN).to include("ai")
    expect(described_class.normalize("ai")).to eq("ai")
    expect(described_class.normalize(:federation)).to eq("federation")
    expect(described_class.normalize("charts")).to eq("other")
  end
end
