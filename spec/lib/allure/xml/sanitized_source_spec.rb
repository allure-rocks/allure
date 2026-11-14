# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Xml::SanitizedSource do
  def read_all(source, chunk_size = 16)
    out = +""
    while (piece = source.read(chunk_size))
      out << piece
      raise "runaway read" if out.bytesize > 1_000_000
    end
    out
  end

  it "strips leading spaces and newlines before the declaration" do
    source = described_class.new(StringIO.new("   \n  <?xml version='1.0'?><a/>"))

    expect(read_all(source)).to eq("<?xml version='1.0'?><a/>")
  end

  it "strips a UTF-8 BOM" do
    content = "\xEF\xBB\xBF<?xml version='1.0'?><a/>".b

    expect(read_all(described_class.new(StringIO.new(content)))).to eq("<?xml version='1.0'?><a/>")
  end

  it "handles a prologue longer than the read size" do
    content = (" " * 5_000) + "<a/>"

    expect(read_all(described_class.new(StringIO.new(content)))).to eq("<a/>")
  end

  it "preserves a document without a prologue" do
    content = "<a><b/></a>"

    expect(read_all(described_class.new(StringIO.new(content)))).to eq(content)
  end

  it "does not strip whitespace after the first markup character" do
    content = "<a>   </a>"

    expect(read_all(described_class.new(StringIO.new(content)))).to eq(content)
  end

  it "reads the whole remaining document with a nil length" do
    source = described_class.new(StringIO.new("  <a/>"))

    expect(source.read).to eq("<a/>")
    expect(source.read).to be_nil
  end

  it "returns nil at end of file" do
    source = described_class.new(StringIO.new("<a/>"))

    expect(source.read(10)).to eq("<a/>")
    expect(source.read(10)).to be_nil
  end

  it "reports end of file after the prologue is consumed" do
    source = described_class.new(StringIO.new("   <a/>"))

    expect(source.eof?).to be(false)
    read_all(source)
    expect(source.eof?).to be(true)
  end
end
