# frozen_string_literal: true

module Allure
  module Fit
    # Decodes the Garmin FIT binary container into named messages. Knows
    # nothing about workouts, sports, or Active Record: it turns bytes into
    # `Message` values and lets `Allure::Fit::Parser` interpret them.
    #
    # Handles the parts of the container that fail *silently* when omitted,
    # which is why each is called out in docs/dev/FIT.md:
    #
    # - normal and compressed-timestamp record headers;
    # - little- and big-endian definition messages;
    # - developer data fields, consumed by declared size without being
    #   interpreted;
    # - chained files, where a second complete FIT file follows the first;
    # - per-base-type "invalid" sentinels, which decode to nil.
    #
    # Unknown global messages, unknown fields, and unknown base types are
    # skipped by their declared size. Field sizes come from the definition
    # message rather than from the base type, so an unrecognised type can
    # never desynchronise the stream.
    class Decoder
      # The importer caps uploads well below this; the limit exists so the
      # decoder is also safe when called directly.
      MAX_BYTES = 25 * 1024 * 1024
      # Garmin devices and exports chain an activity file with many small
      # companion files (the conformance corpus reaches 36); MAX_BYTES is the
      # real bound on the work, this cap only stops a pathological loop.
      MAX_CHAINED_FILES = 64
      SIGNATURE = "\x2E\x46\x49\x54"
      HEADER_SIZES = [ 12, 14 ].freeze
      TIMESTAMP_FIELD = 253

      # FIT CRC-16, nibble-wise lookup table (FIT Protocol, section 3.3.2).
      CRC_TABLE = [
        0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
        0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400
      ].freeze

      # Base type number (base type byte & 0x1F) => decoding rules.
      # `pack` is [little-endian directive, big-endian directive].
      BASE_TYPES = {
        0  => { size: 1, invalid: 0xFF, pack: %w[C C] },
        1  => { size: 1, invalid: 0x7F, pack: %w[c c] },
        2  => { size: 1, invalid: 0xFF, pack: %w[C C] },
        3  => { size: 2, invalid: 0x7FFF, pack: [ "s<", "s>" ] },
        4  => { size: 2, invalid: 0xFFFF, pack: [ "S<", "S>" ] },
        5  => { size: 4, invalid: 0x7FFFFFFF, pack: [ "l<", "l>" ] },
        6  => { size: 4, invalid: 0xFFFFFFFF, pack: [ "L<", "L>" ] },
        7  => { size: 1, string: true },
        8  => { size: 4, invalid: :all_bits, pack: %w[e g] },
        9  => { size: 8, invalid: :all_bits, pack: %w[E G] },
        10 => { size: 1, invalid: 0x00, pack: %w[C C] },
        11 => { size: 2, invalid: 0x0000, pack: [ "S<", "S>" ] },
        12 => { size: 4, invalid: 0x00000000, pack: [ "L<", "L>" ] },
        13 => { size: 1, invalid: 0xFF, pack: %w[C C] },
        14 => { size: 8, invalid: 0x7FFFFFFFFFFFFFFF, pack: [ "q<", "q>" ] },
        15 => { size: 8, invalid: 0xFFFFFFFFFFFFFFFF, pack: [ "Q<", "Q>" ] },
        16 => { size: 8, invalid: 0x0000000000000000, pack: [ "Q<", "Q>" ] }
      }.freeze

      # One decoded data message. `fields` is keyed by profile field name;
      # fields absent from the profile are dropped rather than exposed by
      # number, so callers cannot depend on unnamed data.
      Message = Data.define(:name, :fields)

      FieldDefinition = Data.define(:number, :size, :base_type)
      MessageDefinition = Data.define(:global_message_number, :big_endian, :fields, :total_size)

      def initialize(verify_crc: true)
        @verify_crc = verify_crc
      end

      # Yields each recognised `Message` in file order. Returns an Enumerator
      # when no block is given.
      def decode(io, &block)
        return enum_for(:decode, io) unless block

        data = read_all(io)
        offset = 0
        files = 0

        while offset < data.bytesize
          files += 1
          raise MalformedFitError, "more than #{MAX_CHAINED_FILES} chained FIT files" if files > MAX_CHAINED_FILES

          offset = decode_file(data, offset, &block)
        end

        raise MalformedFitError, "empty FIT stream" if files.zero?
      end

      private

      def read_all(io)
        io.rewind if io.respond_to?(:rewind)
        data = io.read(MAX_BYTES + 1)
        raise MalformedFitError, "empty FIT stream" if data.nil? || data.empty?
        raise MalformedFitError, "FIT file larger than #{MAX_BYTES} bytes" if data.bytesize > MAX_BYTES

        data.b
      end

      # Decodes one complete FIT file starting at `start` and returns the
      # offset immediately after its trailing CRC, which is where a chained
      # file would begin.
      def decode_file(data, start, &block)
        header_size = byte_at(data, start, "file header")
        unless HEADER_SIZES.include?(header_size)
          raise MalformedFitError, "unsupported FIT header size: #{header_size}"
        end

        require_bytes!(data, start, header_size, "file header")

        unless data.byteslice(start + 8, 4) == SIGNATURE.b
          raise MalformedFitError, "missing .FIT signature"
        end

        data_size = data.byteslice(start + 4, 4).unpack1("V")
        verify_header_crc!(data, start) if header_size == 14

        data_start = start + header_size
        data_end = data_start + data_size
        require_bytes!(data, start, header_size + data_size + 2, "record data")

        decode_records(data, data_start, data_end, &block)
        verify_file_crc!(data, start, header_size + data_size)

        data_end + 2
      end

      def verify_header_crc!(data, start)
        stored = data.byteslice(start + 12, 2).unpack1("v")
        # A zero header CRC means "not computed" and is explicitly allowed.
        return if stored.zero? || !@verify_crc

        computed = crc16(data, start, 12)
        return if computed == stored

        raise MalformedFitError, format("header CRC mismatch: expected 0x%04X, got 0x%04X", stored, computed)
      end

      def verify_file_crc!(data, start, length)
        return unless @verify_crc

        stored = data.byteslice(start + length, 2).unpack1("v")
        computed = crc16(data, start, length)
        return if computed == stored

        raise MalformedFitError, format("file CRC mismatch: expected 0x%04X, got 0x%04X", stored, computed)
      end

      def decode_records(data, data_start, data_end, &block)
        definitions = {}
        last_timestamp = nil
        position = data_start

        while position < data_end
          header = byte_at(data, position, "record header")
          position += 1

          if header.anybits?(0x80)
            position, last_timestamp = read_compressed_message(
              data, position, data_end, definitions, header, last_timestamp, &block
            )
          elsif header.anybits?(0x40)
            local_type = header & 0x0F
            definitions[local_type], position = read_definition(data, position, data_end, header.anybits?(0x20))
          else
            position, last_timestamp = read_normal_message(
              data, position, data_end, definitions, header, last_timestamp, &block
            )
          end
        end

        raise MalformedFitError, "record data overran the declared data size" if position != data_end
      end

      def read_definition(data, position, data_end, developer_fields)
        require_range!(data, position, 5, data_end, "definition message")

        big_endian = data.getbyte(position + 1) == 1
        global_message_number = data.byteslice(position + 2, 2).unpack1(big_endian ? "n" : "v")
        field_count = data.getbyte(position + 4)
        position += 5

        require_range!(data, position, field_count * 3, data_end, "definition fields")
        fields = Array.new(field_count) do |index|
          base = position + (index * 3)
          FieldDefinition.new(
            number: data.getbyte(base),
            size: data.getbyte(base + 1),
            base_type: data.getbyte(base + 2) & 0x1F
          )
        end
        position += field_count * 3

        if developer_fields
          require_range!(data, position, 1, data_end, "developer field count")
          developer_count = data.getbyte(position)
          position += 1
          require_range!(data, position, developer_count * 3, data_end, "developer field definitions")

          # Developer fields are not interpreted, but their declared sizes
          # must be consumed or every later field reads at the wrong offset.
          developer_count.times do |index|
            fields << FieldDefinition.new(number: nil, size: data.getbyte(position + (index * 3) + 1), base_type: nil)
          end
          position += developer_count * 3
        end

        definition = MessageDefinition.new(
          global_message_number:,
          big_endian:,
          fields: fields.freeze,
          total_size: fields.sum(&:size)
        )
        [ definition, position ]
      end

      def read_normal_message(data, position, data_end, definitions, header, last_timestamp, &block)
        definition = definition_for(definitions, header & 0x0F)
        fields, raw_timestamp, position = read_fields(data, position, data_end, definition)
        last_timestamp = raw_timestamp if raw_timestamp
        emit(definition, fields, &block)
        [ position, last_timestamp ]
      end

      def read_compressed_message(data, position, data_end, definitions, header, last_timestamp, &block)
        definition = definition_for(definitions, (header >> 5) & 0x03)
        if last_timestamp.nil?
          raise MalformedFitError, "compressed timestamp header before any full timestamp"
        end

        # FIT Protocol section 4.2: the 5-bit offset rolls over relative to
        # the low five bits of the previous timestamp.
        last_timestamp += ((header & 0x1F) - last_timestamp) & 0x1F

        fields, raw_timestamp, position = read_fields(data, position, data_end, definition)
        last_timestamp = raw_timestamp if raw_timestamp
        fields[:timestamp] ||= last_timestamp if definition_names_timestamp?(definition)
        emit(definition, fields, &block)
        [ position, last_timestamp ]
      end

      def definition_for(definitions, local_type)
        definitions[local_type] ||
          raise(MalformedFitError, "data message for undefined local message type #{local_type}")
      end

      def definition_names_timestamp?(definition)
        message_name = Profile.message_name(definition.global_message_number)
        message_name && Profile.field_name(message_name, TIMESTAMP_FIELD)
      end

      # Returns [named fields, raw field-253 value, new position]. The raw
      # timestamp is tracked for every message, named or not, because the
      # compressed-timestamp rollover depends on it.
      def read_fields(data, position, data_end, definition)
        require_range!(data, position, definition.total_size, data_end, "data message")

        message_name = Profile.message_name(definition.global_message_number)
        fields = {}
        raw_timestamp = nil

        definition.fields.each do |field|
          bytes = data.byteslice(position, field.size)
          position += field.size
          next if field.number.nil?

          value = decode_value(bytes, field.base_type, definition.big_endian)
          next if value.nil?

          raw_timestamp = value if field.number == TIMESTAMP_FIELD && value.is_a?(Integer)
          name = message_name && Profile.field_name(message_name, field.number)
          fields[name] = value if name
        end

        [ fields, raw_timestamp, position ]
      end

      def emit(definition, fields)
        name = Profile.message_name(definition.global_message_number)
        return unless name

        yield Message.new(name:, fields: fields.freeze)
      end

      def decode_value(bytes, base_type, big_endian)
        rules = BASE_TYPES[base_type]
        return nil unless rules
        return decode_string(bytes) if rules[:string]
        return nil if bytes.bytesize < rules[:size]

        # A field larger than its base type is an array; scalars take the
        # first element, matching how devices emit single-element tuples.
        scalar = bytes.byteslice(0, rules[:size])
        directive = rules[:pack][big_endian ? 1 : 0]
        return nil if invalid?(scalar, rules, directive)

        scalar.unpack1(directive)
      end

      # The invalid sentinel is a value, not a byte pattern, so it must be
      # compared against a read using the message's own architecture. Reading
      # it little-endian would miss every sentinel in a big-endian message.
      def invalid?(scalar, rules, directive)
        return scalar.each_byte.all?(0xFF) if rules[:invalid] == :all_bits

        scalar.unpack1(directive) == rules[:invalid]
      end

      def decode_string(bytes)
        terminator = bytes.index("\x00".b)
        raw = terminator ? bytes.byteslice(0, terminator) : bytes
        value = raw.force_encoding(Encoding::UTF_8).encode("UTF-8", invalid: :replace, undef: :replace).strip
        value.empty? ? nil : value
      end

      def crc16(data, start, length)
        crc = 0
        data.byteslice(start, length).each_byte do |byte|
          tmp = CRC_TABLE[crc & 0x0F]
          crc = ((crc >> 4) & 0x0FFF) ^ tmp ^ CRC_TABLE[byte & 0x0F]
          tmp = CRC_TABLE[crc & 0x0F]
          crc = ((crc >> 4) & 0x0FFF) ^ tmp ^ CRC_TABLE[(byte >> 4) & 0x0F]
        end
        crc
      end

      def byte_at(data, position, label)
        data.getbyte(position) || raise(MalformedFitError, "truncated #{label}")
      end

      def require_bytes!(data, start, length, label)
        return if data.bytesize >= start + length

        raise MalformedFitError, "truncated #{label}"
      end

      def require_range!(data, position, length, data_end, label)
        return if position + length <= data_end && position + length <= data.bytesize

        raise MalformedFitError, "truncated #{label}"
      end
    end
  end
end
