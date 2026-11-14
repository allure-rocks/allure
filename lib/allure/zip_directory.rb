# frozen_string_literal: true

module Allure
  # Reads how many entries a ZIP's central directory declares from its end
  # records alone, without building anything. rubyzip parses the whole
  # directory into objects as it opens an archive, reading exactly that many
  # entries, so this count bounds its work before it starts.
  #
  # The end record is found as rubyzip finds it — the last signature in the
  # final 64 KiB plus its fixed size — and a Zip64 record, when its locator
  # precedes the end record, is read too; the larger count wins, so the
  # result never falls short of what rubyzip will read.
  module ZipDirectory
    EOCD_SIGNATURE = [ 0x06054b50 ].pack("V").freeze
    ZIP64_LOCATOR_SIGNATURE = 0x07064b50
    ZIP64_EOCD_SIGNATURE = 0x06064b50
    EOCD_SIZE = 22
    ZIP64_LOCATOR_SIZE = 20
    ZIP64_EOCD_SIZE = 56
    MAX_COMMENT = 0xFFFF

    module_function

    # The declared entry count, or nil when the input has no end record.
    def entry_count(io)
      return nil unless io.respond_to?(:seek) && io.respond_to?(:read) && io.respond_to?(:size)

      size = io.size
      return nil if size < EOCD_SIZE

      tail_size = [ size, EOCD_SIZE + MAX_COMMENT ].min
      tail = read_at(io, size - tail_size, tail_size)
      position = tail&.rindex(EOCD_SIGNATURE)
      return nil if position.nil? || tail.bytesize - position < EOCD_SIZE

      count = tail.byteslice(position + 10, 2).unpack1("v")
      [ count, zip64_count(io, size - tail_size + position) ].compact.max
    ensure
      io.rewind if io.respond_to?(:rewind)
    end

    def zip64_count(io, eocd_offset)
      return nil if eocd_offset < ZIP64_LOCATOR_SIZE

      locator = read_at(io, eocd_offset - ZIP64_LOCATOR_SIZE, ZIP64_LOCATOR_SIZE)
      return nil unless locator&.bytesize == ZIP64_LOCATOR_SIZE && locator.unpack1("V") == ZIP64_LOCATOR_SIGNATURE

      record_offset = locator.byteslice(8, 8).unpack1("Q<")
      record = read_at(io, record_offset, ZIP64_EOCD_SIZE)
      return nil unless record&.bytesize == ZIP64_EOCD_SIZE && record.unpack1("V") == ZIP64_EOCD_SIGNATURE

      record.byteslice(32, 8).unpack1("Q<")
    end

    def read_at(io, offset, length)
      io.seek(offset, IO::SEEK_SET)
      io.read(length)&.b
    end
  end
end
