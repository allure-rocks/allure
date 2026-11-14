# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Fit::Decoder do
  subject(:decoder) { described_class.new }

  def messages(bytes) = decoder.decode(StringIO.new(bytes.b)).to_a

  # A record definition without field 253, for use with compressed
  # timestamp headers, which exist precisely to omit the timestamp.
  UNTIMED_RECORD = [ [ 0, :sint32 ], [ 1, :sint32 ] ].freeze
  TIMED_RECORD = [ [ 253, :uint32 ], [ 0, :sint32 ], [ 1, :sint32 ] ].freeze

  describe "container structure" do
    it "decodes a 14-byte header file into named messages and fields" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ], [ 1, :uint16 ] ])
        .data(local: 0, values: [ 4, 1 ])
        .to_s

      expect(messages(bytes)).to eq(
        [ described_class::Message.new(name: :file_id, fields: { type: 4, manufacturer: 1 }) ]
      )
    end

    it "decodes a 12-byte header file, which carries no header CRC" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .to_s(header_size: 12)

      expect(messages(bytes).first.fields).to eq({ type: 4 })
    end

    it "accepts a zero header CRC, which the specification defines as not computed" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .to_s(header_crc: 0)

      expect(messages(bytes).length).to eq(1)
    end

    it "continues into a chained file rather than stopping at the first" do
      first = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 2 ])
        .to_s
      second = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .to_s

      expect(messages(FitBuilder.chain(first, second)).map { it.fields[:type] }).to eq([ 2, 4 ])
    end

    it "accepts a long chain of companion files" do
      files = Array.new(20) do |index|
        FitBuilder.new
          .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
          .data(local: 0, values: [ index.zero? ? 4 : 2 ])
          .to_s
      end

      expect(messages(FitBuilder.chain(*files)).length).to eq(20)
    end

    it "rejects a chain beyond the chained-file cap" do
      file = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 2 ])
        .to_s

      expect { messages(FitBuilder.chain(*Array.new(65, file))) }
        .to raise_error(Allure::Fit::MalformedFitError, /chained FIT files/)
    end
  end

  describe "definition messages" do
    it "reads big-endian definitions and their data" do
      bytes = FitBuilder.new
        .define(local: 0, global: 20, fields: TIMED_RECORD, big_endian: true)
        .data(local: 0, values: [ 1_000_000, 536_870_912, -536_870_912 ])
        .to_s

      expect(messages(bytes).first.fields).to eq(
        { timestamp: 1_000_000, position_lat: 536_870_912, position_long: -536_870_912 }
      )
    end

    it "consumes developer fields by declared size so later fields stay aligned" do
      bytes = FitBuilder.new
        .define(local: 0, global: 20, fields: TIMED_RECORD, developer_fields: [ [ 0, 4 ] ])
        .data(local: 0, values: [ 1_000_000, 10, 20 ], developer_values: [ "\xDE\xAD\xBE\xEF" ])
        .define(local: 1, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 1, values: [ 4 ])
        .to_s

      expect(messages(bytes).map(&:name)).to eq(%i[record file_id])
      expect(messages(bytes).last.fields).to eq({ type: 4 })
    end

    it "replaces a redefined local message type instead of merging it" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ], [ 1, :uint16 ] ])
        .data(local: 0, values: [ 4, 1 ])
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 6 ])
        .to_s

      expect(messages(bytes).map(&:fields)).to eq([ { type: 4, manufacturer: 1 }, { type: 6 } ])
    end

    it "skips unknown global messages without desynchronising the stream" do
      bytes = FitBuilder.new
        .define(local: 0, global: 999, fields: [ [ 0, :uint32 ], [ 1, :uint16 ] ])
        .data(local: 0, values: [ 1, 2 ])
        .define(local: 1, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 1, values: [ 4 ])
        .to_s

      expect(messages(bytes).map(&:name)).to eq([ :file_id ])
    end
  end

  describe "compressed timestamp headers" do
    def compressed_bytes(anchor:, offsets:)
      builder = FitBuilder.new
        .define(local: 3, global: 20, fields: TIMED_RECORD)
        .data(local: 3, values: [ anchor, 10, 20 ])
        .define(local: 0, global: 20, fields: UNTIMED_RECORD)
      offsets.each { |offset| builder.compressed(local: 0, time_offset: offset, values: [ 30, 40 ]) }
      builder.to_s
    end

    it "applies the 5-bit offset to the previous timestamp" do
      anchor = 1_000_000
      bytes = compressed_bytes(anchor:, offsets: [ (anchor + 5) & 0x1F ])

      expect(messages(bytes).last.fields[:timestamp]).to eq(anchor + 5)
    end

    it "rolls the offset over rather than moving backwards" do
      # 0x1F is the largest representable offset, so this crosses a 32-second
      # boundary and must still advance.
      anchor = 1_000_030
      bytes = compressed_bytes(anchor:, offsets: [ (anchor + 4) & 0x1F ])

      expect(messages(bytes).last.fields[:timestamp]).to eq(anchor + 4)
    end

    it "accumulates across consecutive compressed messages" do
      anchor = 1_000_000
      offsets = [ (anchor + 5) & 0x1F, (anchor + 11) & 0x1F, (anchor + 40) & 0x1F ]

      expect(messages(compressed_bytes(anchor:, offsets:)).map { it.fields[:timestamp] })
        .to eq([ anchor, anchor + 5, anchor + 11, anchor + 40 ])
    end

    it "rejects a compressed header before any full timestamp" do
      bytes = FitBuilder.new
        .define(local: 0, global: 20, fields: UNTIMED_RECORD)
        .compressed(local: 0, time_offset: 5, values: [ 10, 20 ])
        .to_s

      expect { messages(bytes) }.to raise_error(Allure::Fit::MalformedFitError, /before any full timestamp/)
    end
  end

  describe "invalid value sentinels" do
    it "decodes each type's sentinel to nil rather than the raw value" do
      bytes = FitBuilder.new
        .define(local: 0, global: 20, fields: [ [ 253, :uint32 ], [ 0, :sint32 ], [ 3, :uint8 ], [ 7, :uint16 ] ])
        .data(local: 0, values: [ 1_000_000, nil, nil, nil ])
        .to_s

      expect(messages(bytes).first.fields).to eq({ timestamp: 1_000_000 })
    end

    it "detects sentinels in big-endian messages, where a little-endian read would miss them" do
      bytes = FitBuilder.new
        .define(local: 0, global: 20, fields: [ [ 253, :uint32 ], [ 0, :sint32 ] ], big_endian: true)
        .data(local: 0, values: [ 1_000_000, nil ])
        .to_s

      expect(messages(bytes).first.fields).to eq({ timestamp: 1_000_000 })
    end
  end

  describe "string fields" do
    it "reads a null-terminated string and drops the padding" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 8, :string, 16 ] ])
        .data(local: 0, values: [ "Edge 1050" ])
        .to_s

      expect(messages(bytes).first.fields).to eq({ product_name: "Edge 1050" })
    end

    it "omits an empty string rather than reporting a blank product name" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 8, :string, 8 ] ])
        .data(local: 0, values: [ "" ])
        .to_s

      expect(messages(bytes).first.fields).to eq({})
    end
  end

  describe "malformed input" do
    def expect_malformed(bytes, message)
      expect { messages(bytes) }.to raise_error(Allure::Fit::MalformedFitError, message)
    end

    it "rejects a corrupt file CRC" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .to_s(corrupt_crc: true)

      expect_malformed(bytes, /file CRC mismatch/)
    end

    it "rejects a corrupt header CRC" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .to_s(header_crc: 0x1234)

      expect_malformed(bytes, /header CRC mismatch/)
    end

    it "rejects a missing .FIT signature" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .to_s
        .dup
      bytes[8, 4] = "XXXX"

      expect_malformed(bytes, /missing \.FIT signature/)
    end

    it "rejects an unsupported header size" do
      expect_malformed("\x0A" + ("\x00" * 20), /unsupported FIT header size/)
    end

    it "rejects a truncated file" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .to_s

      expect_malformed(bytes.byteslice(0, bytes.bytesize - 4), /truncated/)
    end

    it "rejects a data message for an undefined local message type" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .raw("\x05\x04")
        .to_s

      expect_malformed(bytes, /undefined local message type 5/)
    end

    it "rejects an empty stream" do
      expect_malformed("", /empty FIT stream/)
    end
  end

  describe "CRC verification opt-out" do
    it "decodes a corrupt-CRC file when verification is disabled" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .to_s(corrupt_crc: true)

      lenient = described_class.new(verify_crc: false)

      expect(lenient.decode(StringIO.new(bytes.b)).to_a.length).to eq(1)
    end
  end
end
