# frozen_string_literal: true

# A deterministic FIT encoder used to build fixtures in-memory.
#
# FIT fixtures are generated rather than committed. Real activity files are
# other people's GPS traces, which AGENTS.md forbids committing, and a binary
# blob cannot be reviewed in a diff. Building the bytes here keeps every
# fixture readable and lets a spec construct exactly the container feature it
# is exercising: compressed timestamp headers, big-endian definitions,
# developer fields, chained files, or a deliberately corrupt CRC.
class FitBuilder
  CRC_TABLE = [
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400
  ].freeze

  # name => [base type byte, size, little-endian pack, big-endian pack, invalid]
  TYPES = {
    enum: [ 0x00, 1, "C", "C", 0xFF ],
    sint8: [ 0x01, 1, "c", "c", 0x7F ],
    uint8: [ 0x02, 1, "C", "C", 0xFF ],
    sint16: [ 0x83, 2, "s<", "s>", 0x7FFF ],
    uint16: [ 0x84, 2, "S<", "S>", 0xFFFF ],
    sint32: [ 0x85, 4, "l<", "l>", 0x7FFFFFFF ],
    uint32: [ 0x86, 4, "L<", "L>", 0xFFFFFFFF ],
    string: [ 0x07, nil, nil, nil, nil ],
    float32: [ 0x88, 4, "e", "g", nil ]
  }.freeze

  FIT_EPOCH_OFFSET = 631_065_600
  SEMICIRCLES_PER_DEGREE = (2**31) / 180.0

  def self.semicircles(degrees) = (degrees * SEMICIRCLES_PER_DEGREE).round

  def self.fit_time(time) = time.to_i - FIT_EPOCH_OFFSET

  def initialize
    @body = +"".b
    @definitions = {}
  end

  # Emits a definition message and remembers its field layout so subsequent
  # `data` calls can pack values positionally.
  #
  # fields: [[field_number, type_symbol, size_override], ...]
  def define(local:, global:, fields:, big_endian: false, developer_fields: [])
    @definitions[local] = { fields:, big_endian: }

    header = 0x40 | (local & 0x0F)
    header |= 0x20 if developer_fields.any?
    record = [ header, 0, big_endian ? 1 : 0 ].pack("C3")
    record << [ global ].pack(big_endian ? "n" : "v")
    record << [ fields.length ].pack("C")
    fields.each do |number, type, size|
      base, base_size, = TYPES.fetch(type)
      record << [ number, size || base_size, base ].pack("C3")
    end

    if developer_fields.any?
      record << [ developer_fields.length ].pack("C")
      developer_fields.each { |number, size| record << [ number, size, 0 ].pack("C3") }
    end

    @body << record
    self
  end

  # values: positional, matching the definition's field order. nil packs the
  # type's "invalid" sentinel. developer_values are opaque byte strings.
  def data(local:, values:, developer_values: [])
    @body << [ local & 0x0F ].pack("C")
    @body << pack_values(local, values)
    developer_values.each { |bytes| @body << bytes.b }
    self
  end

  # A compressed-timestamp data message. `local` is 2 bits wide here.
  def compressed(local:, time_offset:, values:)
    @body << [ 0x80 | ((local & 0x03) << 5) | (time_offset & 0x1F) ].pack("C")
    @body << pack_values(local, values)
    self
  end

  def raw(bytes)
    @body << bytes.b
    self
  end

  # Serializes header + records + CRC. `corrupt_crc` flips the trailing CRC so
  # a spec can assert integrity checking without hand-writing bytes.
  def to_s(header_size: 14, corrupt_crc: false, header_crc: :computed)
    header = build_header(header_size, header_crc)
    file = header + @body
    crc = self.class.crc16(file)
    crc = (crc ^ 0xFFFF) if corrupt_crc
    file + [ crc ].pack("v")
  end

  # Concatenates already-serialized FIT files, producing a chained file.
  def self.chain(*files) = files.map(&:b).join

  def self.crc16(bytes)
    crc = 0
    bytes.b.each_byte do |byte|
      tmp = CRC_TABLE[crc & 0x0F]
      crc = ((crc >> 4) & 0x0FFF) ^ tmp ^ CRC_TABLE[byte & 0x0F]
      tmp = CRC_TABLE[crc & 0x0F]
      crc = ((crc >> 4) & 0x0FFF) ^ tmp ^ CRC_TABLE[(byte >> 4) & 0x0F]
    end
    crc
  end

  private

  def build_header(header_size, header_crc)
    header = [ header_size, 0x20, 2108 ].pack("CCv")
    header << [ @body.bytesize ].pack("V")
    header << ".FIT".b
    return header if header_size == 12

    value = header_crc == :computed ? self.class.crc16(header) : header_crc
    header << [ value ].pack("v")
  end

  def pack_values(local, values)
    definition = @definitions.fetch(local)
    big_endian = definition[:big_endian]

    definition[:fields].each_with_index.map do |(_number, type, size), index|
      pack_value(values[index], type, size, big_endian)
    end.join
  end

  def pack_value(value, type, size, big_endian)
    _base, base_size, little, big, invalid = TYPES.fetch(type)

    if type == :string
      width = size || (value.to_s.bytesize + 1)
      return value.to_s.b.ljust(width, "\x00").byteslice(0, width)
    end

    directive = big_endian ? big : little
    return [ value ].pack(directive) unless value.nil?
    # Float has no integer sentinel; its invalid value is all bits set.
    return "\xFF".b * base_size if invalid.nil?

    [ invalid ].pack(directive)
  end
end

# Fixture helpers for the common shape: one activity file with a file_id, a
# session, an optional stop_all event, and a run of records.
module FitFixtureHelpers
  RECORD_FIELDS = [
    [ 253, :uint32 ],
    [ 0, :sint32 ],
    [ 1, :sint32 ],
    [ 2, :uint16 ],
    [ 3, :uint8 ],
    [ 4, :uint8 ],
    [ 5, :uint32 ],   # distance, cm
    [ 7, :uint16 ],
    [ 73, :uint32 ]   # enhanced_speed, mm/s
  ].freeze

  FILE_ID_FIELDS = [
    [ 0, :enum ], [ 1, :uint16 ], [ 2, :uint16 ], [ 3, :uint32 ], [ 8, :string, 24 ]
  ].freeze
  # Session field numbers are offset by one from the lap numbers below: 21 is
  # `max_power`, 22 `total_ascent`, 23 `total_descent`.
  SESSION_FIELDS = [
    [ 5, :enum ], [ 6, :enum ], [ 11, :uint16 ],
    [ 15, :uint16 ], [ 125, :uint32 ],
    [ 21, :uint16 ], [ 22, :uint16 ], [ 23, :uint16 ]
  ].freeze
  EVENT_FIELDS = [ [ 253, :uint32 ], [ 0, :enum ], [ 1, :enum ] ].freeze

  # Field order and scales for a global `lap` message (global 19).
  LAP_FIELDS = [
    [ 253, :uint32 ], # timestamp
    [ 254, :uint16 ], # message_index (0-based)
    [ 7, :uint32 ],   # total_elapsed_time (s * 1000)
    [ 8, :uint32 ],   # total_timer_time (s * 1000)
    [ 9, :uint32 ],   # total_distance (m * 100)
    [ 13, :uint16 ],  # avg_speed (m/s * 1000)
    [ 14, :uint16 ],  # max_speed (m/s * 1000)
    [ 15, :uint8 ],   # avg_heart_rate
    [ 16, :uint8 ],   # max_heart_rate
    [ 17, :uint8 ],   # avg_cadence
    [ 19, :uint16 ],  # avg_power
    [ 21, :uint16 ],  # total_ascent
    [ 22, :uint16 ],  # total_descent
    [ 24, :enum ],    # lap_trigger
    [ 52, :uint32 ],  # total_moving_time (s * 1000)
    [ 110, :uint32 ], # enhanced_avg_speed (m/s * 1000)
    [ 111, :uint32 ]  # enhanced_max_speed (m/s * 1000)
  ].freeze

  FILE_TYPES = { activity: 4, course: 6, settings: 2, workout: 5 }.freeze

  # points: [{ time:, lat:, lon:, altitude: nil, hr: nil, cadence: nil, power: nil, speed: nil,
  #            distance: nil }] — `distance` is the device's cumulative distance in metres
  #          (a positionless recording's own source, PLAN_NO_GPS.md §3.2).
  # stops:  [Time] — each becomes a timer/stop_all event
  # laps:   [{ time:, elapsed:, moving: nil, distance: nil, avg_speed: nil,
  #            max_speed: nil, avg_heart_rate: nil, max_heart_rate: nil,
  #            avg_cadence: nil, avg_power: nil, lap_trigger: nil }]
  #          Values describe each lap independently, as required by FIT.
  # record_latlon_type: :uint32 reproduces devices that misdeclare the
  #   semicircle fields; the profile mandates :sint32.
  def build_fit(points:, stops: [], laps: [], sport: nil, sub_sport: nil, calories: nil,
                max_speed: nil, enhanced_max_speed: nil,
                session_max_power: nil, session_ascent: nil, session_descent: nil,
                product_name: "Allure Test Device", manufacturer: 1,
                product: nil, serial_number: nil,
                file_type: :activity, header_size: 14, corrupt_crc: false,
                big_endian: false, record_latlon_type: :sint32)
    builder = FitBuilder.new

    builder.define(local: 0, global: 0, fields: FILE_ID_FIELDS, big_endian:)
    builder.data(
      local: 0,
      values: [ FILE_TYPES.fetch(file_type), manufacturer, product, serial_number, product_name ]
    )

    if sport || sub_sport || calories || max_speed || enhanced_max_speed ||
       session_max_power || session_ascent || session_descent
      builder.define(local: 1, global: 18, fields: SESSION_FIELDS, big_endian:)
      builder.data(local: 1, values: [
        sport, sub_sport, calories,
        max_speed && (max_speed * 1000),
        enhanced_max_speed && (enhanced_max_speed * 1000),
        session_max_power, session_ascent, session_descent
      ])
    end

    if stops.any?
      builder.define(local: 2, global: 21, fields: EVENT_FIELDS, big_endian:)
      stops.each do |time|
        builder.data(local: 2, values: [ FitBuilder.fit_time(time), 0, 4 ])
      end
    end

    builder.define(local: 3, global: 20, fields: record_fields(record_latlon_type), big_endian:)
    points.each { |point| builder.data(local: 3, values: record_values(point)) }

    if laps.any?
      builder.define(local: 4, global: 19, fields: LAP_FIELDS, big_endian:)
      laps.each_with_index do |lap, index|
        builder.data(local: 4, values: [
          FitBuilder.fit_time(lap.fetch(:time)),
          lap.fetch(:message_index, index),
          lap[:elapsed] && (lap[:elapsed] * 1000),
          lap[:elapsed] && (lap[:elapsed] * 1000),
          lap[:distance] && (lap[:distance] * 100),
          lap[:avg_speed] && (lap[:avg_speed] * 1000),
          lap[:max_speed] && (lap[:max_speed] * 1000),
          lap[:avg_heart_rate],
          lap[:max_heart_rate],
          lap[:avg_cadence],
          lap[:avg_power],
          lap[:ascent],
          lap[:descent],
          lap[:lap_trigger],
          lap[:moving] && (lap[:moving] * 1000),
          lap[:enhanced_avg_speed] && (lap[:enhanced_avg_speed] * 1000),
          lap[:enhanced_max_speed] && (lap[:enhanced_max_speed] * 1000)
        ])
      end
    end

    builder.to_s(header_size:, corrupt_crc:)
  end

  def fit_io(bytes) = StringIO.new(bytes.b)

  # Rack::Test::UploadedFile needs a real path, so the bytes are written to a
  # Tempfile. The default content type is what browsers actually send for a
  # .fit on most platforms, which is the case the importer must handle.
  def fit_upload(bytes, filename: "ride.fit", content_type: "application/octet-stream")
    file = Tempfile.new([ "allure-fit-", ".fit" ])
    file.binmode
    file.write(bytes.b)
    file.rewind
    # Kept in an ivar so the Tempfile is not finalized mid-request.
    (@fit_uploads ||= []) << file
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: filename)
  end

  def parse_fit(bytes, **options) = Allure::Fit::Parser.new(**options).parse(fit_io(bytes))

  def record_fields(latlon_type)
    RECORD_FIELDS.map do |field|
      [ 0, 1 ].include?(field[0]) ? [ field[0], latlon_type ] : field
    end
  end

  def record_values(point)
    [
      FitBuilder.fit_time(point.fetch(:time)),
      point[:lat] && FitBuilder.semicircles(point[:lat]),
      point[:lon] && FitBuilder.semicircles(point[:lon]),
      point[:altitude] && ((point[:altitude] + 500.0) * 5).round,
      point[:hr],
      point[:cadence],
      point[:distance] && (point[:distance] * 100).round,
      point[:power],
      point[:speed] && (point[:speed] * 1000).round
    ]
  end

  # A minimal, valid three-point activity used wherever the track itself is
  # not what the example is about.
  def simple_fit_points(start: Time.utc(2026, 5, 1, 8, 0, 0))
    [
      { time: start, lat: 45.0640, lon: 6.4077, altitude: 2000.0 },
      { time: start + 60, lat: 45.0650, lon: 6.4090, altitude: 2010.0 },
      { time: start + 120, lat: 45.0660, lon: 6.4103, altitude: 2020.0 }
    ]
  end
end

RSpec.configure do |config|
  config.include FitFixtureHelpers
end
