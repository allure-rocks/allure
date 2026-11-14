# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::ZipDirectory do
  def archive(entries, comment: nil)
    Zip::OutputStream.write_buffer do |zip|
      zip.comment = comment if comment
      entries.each do |name|
        zip.put_next_entry(name)
        zip.write("x") unless name.end_with?("/")
      end
    end
  end

  it "reads the entry count of an ordinary archive, folders included" do
    io = archive(%w[rides/ rides/one.gpx rides/two.gpx])

    expect(described_class.entry_count(io)).to eq(3)
    expect(io.pos).to eq(0)
  end

  it "finds the end record behind a comment" do
    expect(described_class.entry_count(archive(%w[one.gpx], comment: "PK made by hand" * 100))).to eq(1)
  end

  it "reads the Zip64 count when the end record defers to it" do
    expect(described_class.entry_count(StringIO.new(zip_declaring(2_000_000)))).to eq(2_000_000)
  end

  it "reads a count declared without any entry" do
    expect(described_class.entry_count(StringIO.new(zip_declaring(40_000, comment: "bomb")))).to eq(40_000)
  end

  it "answers nil for anything without an end record" do
    expect(described_class.entry_count(StringIO.new("not a zip at all, just text"))).to be_nil
    expect(described_class.entry_count(StringIO.new(""))).to be_nil
    expect(described_class.entry_count("a string")).to be_nil
  end
end
