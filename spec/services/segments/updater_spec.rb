# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::Updater do
  # A loop the owner renamed is the identity they chose: the reconciliation
  # elects it and the orphan sweep spares it (docs/dev/SEGMENTS.md).
  it "marks a renamed loop with the rename time" do
    loop_segment = create(:segment, :loop)

    described_class.new(segment: loop_segment, attributes: { "name" => "Tour du lac" }).call

    expect(loop_segment.reload).to have_attributes(name: "Tour du lac", renamed_at: be_present)
  end

  it "keeps the mark when the name is set back to the generated form" do
    loop_segment = create(:segment, :loop, name: "Tour du lac", renamed_at: 1.day.ago)

    described_class.new(segment: loop_segment, attributes: { "name" => "Morning ride loop" }).call

    expect(loop_segment.reload.renamed_at).to be_present
  end

  it "leaves a loop unmarked when the name does not change" do
    loop_segment = create(:segment, :loop)

    described_class.new(segment: loop_segment, attributes: { "description" => "Now described" }).call

    expect(loop_segment.reload.renamed_at).to be_nil
  end

  it "does not mark a renamed segment or route" do
    segment = create(:segment)

    described_class.new(segment:, attributes: { "name" => "A new name" }).call

    expect(segment.reload.renamed_at).to be_nil
  end
end
