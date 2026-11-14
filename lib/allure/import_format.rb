# frozen_string_literal: true

module Allure
  # The single source of truth for the file formats Allure can import: their
  # magic bytes, file extension, storage content type, and parser.
  #
  # Both `Workouts::Importer` and `Workouts::ArchiveReader` consume this, so
  # the `.FIT` signature and the accepted extension list are never duplicated.
  #
  # Detection is by content, never by extension. A file's extension is
  # supplied by whoever uploaded or zipped it and carries no authority; its
  # first bytes do. The extension is still validated so the user gets a clear
  # message, but where the two disagree the content wins and determines how
  # the original file is stored.
  module ImportFormat
    Format = Data.define(:key, :extension, :content_type, :parser_class) do
      def parser(**) = parser_class.new(**)
    end

    GPX = Format.new(
      key: "gpx",
      extension: ".gpx",
      content_type: "application/gpx+xml",
      parser_class: Allure::Gpx::Parser
    )

    FIT = Format.new(
      key: "fit",
      extension: ".fit",
      content_type: "application/vnd.ant.fit",
      parser_class: Allure::Fit::Parser
    )

    TCX = Format.new(
      key: "tcx",
      extension: ".tcx",
      content_type: "application/vnd.garmin.tcx+xml",
      parser_class: Allure::Tcx::Parser
    )

    KML = Format.new(
      key: "kml",
      extension: ".kml",
      content_type: "application/vnd.google-earth.kml+xml",
      parser_class: Allure::Kml::Parser
    )

    ALL = [ GPX, FIT, TCX, KML ].freeze
    EXTENSIONS = ALL.map(&:extension).freeze

    # Enough to reach the FIT signature at offset 8 and to see past leading
    # whitespace, a byte-order mark, or an XML declaration.
    SNIFF_BYTES = 1024

    # FIT Protocol section 3.1: byte 0 is the header size, which is 12 or 14,
    # and bytes 8..11 are the ASCII signature.
    FIT_SIGNATURE = ".FIT"
    FIT_SIGNATURE_OFFSET = 8
    FIT_HEADER_SIZES = [ 12, 14 ].freeze

    module_function

    # Returns the detected Format, or nil when the bytes match none. Rewinds
    # the IO before and after so callers can hand the same handle to a parser.
    def detect(io)
      io.rewind if io.respond_to?(:rewind)
      head = io.read(SNIFF_BYTES)
      io.rewind if io.respond_to?(:rewind)
      return nil if head.nil?

      detect_bytes(head)
    rescue IOError, SystemCallError
      nil
    end

    # XML formats are discriminated by their root element inside the sniff
    # window, not by a shared `<?xml` prefix (which would misclaim TCX/KML as
    # GPX). If a long preamble pushes the root past the window, detection
    # fails closed (nil) rather than guessing.
    def detect_bytes(head)
      bytes = head.b
      return FIT if fit?(bytes)

      case root_element_name(bytes)
      when "TrainingCenterDatabase" then TCX
      when "kml" then KML
      when "gpx" then GPX
      end
    end

    def tcx?(bytes)
      root_element_name(bytes) == "TrainingCenterDatabase"
    end

    def kml?(bytes)
      root_element_name(bytes) == "kml"
    end

    def gpx?(bytes)
      root_element_name(bytes) == "gpx"
    end

    def root_element_name(bytes)
      text = bytes.sub(/\A\xEF\xBB\xBF/n, "").lstrip
      loop do
        if text.start_with?("<?")
          close = text.index("?>", 2)
          return nil unless close

          text = text[(close + 2)..].lstrip
        elsif text.start_with?("<!--")
          close = text.index("-->", 4)
          return nil unless close

          text = text[(close + 3)..].lstrip
        elsif text.start_with?("<!")
          close = text.index(">", 2)
          return nil unless close

          text = text[(close + 1)..].lstrip
        else
          break
        end
        return nil if text.nil? || text.empty?
      end
      match = text.match(/\A<([A-Za-z_][\w.-]*)(?::([A-Za-z_][\w.-]*))?[\s>\/]/)
      return nil unless match

      match[2] || match[1]
    end

    def fit?(bytes)
      return false if bytes.bytesize < FIT_SIGNATURE_OFFSET + FIT_SIGNATURE.bytesize
      return false unless FIT_HEADER_SIZES.include?(bytes.getbyte(0))

      bytes.byteslice(FIT_SIGNATURE_OFFSET, FIT_SIGNATURE.bytesize) == FIT_SIGNATURE.b
    end

    def for_extension(extension)
      normalized = extension.to_s.downcase
      ALL.find { |format| format.extension == normalized }
    end

    def for_key(key)
      normalized = key.to_s.downcase
      ALL.find { |format| format.key == normalized }
    end
  end
end
