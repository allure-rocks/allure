# frozen_string_literal: true

require "tempfile"
require "zlib"
require "zip"

module Workouts
  class ArchiveReader
    MAX_SOURCE_BYTES = 500.megabytes
    MAX_ENTRY_BYTES = Importer::MAX_BYTES
    MAX_ARCHIVE_ENTRIES = 1_000
    MAX_SOURCE_FILES = MAX_ARCHIVE_ENTRIES
    MAX_TOTAL_UNCOMPRESSED_BYTES = 2.gigabytes
    MAX_TOTAL_UNCOMPRESSED_LABEL = "2 GB"
    MAX_COMPRESSION_RATIO = 1_000
    # Every entry the central directory declares, folders included, checked
    # before rubyzip builds one object per entry (docs/dev/IMPORT-SOURCES.md).
    MAX_DIRECTORY_ENTRIES = 10_000
    CHUNK_SIZE = 64 * 1024

    class Error < StandardError; end

    Entry = Data.define(:name, :index, :io)
    ManifestEntry = Data.define(:name, :index)

    def initialize
      @total_uncompressed_bytes = 0
    end

    def each_entry(source, filename:)
      validate_source_size!(source)
      filename = utf8(filename)

      case File.extname(filename.to_s).downcase
      when *Allure::ImportFormat::EXTENSIONS
        reserve_uncompressed!(source.size.to_i)
        rewind(source)
        yield Entry.new(name: File.basename(filename), index: 0, io: source)
      when ".gz"
        each_gzip_entry(source, filename) { yield it }
      when ".kmz"
        each_kmz_entry(source, filename) { yield it }
      when ".zip"
        each_zip_entry(source) { yield it }
      else
        raise Error, I18n.t("workouts.batch_import.errors.unsupported_source")
      end
    rescue Zlib::Error, Zip::Error, IOError => error
      raise Error, I18n.t("workouts.batch_import.errors.malformed_archive", error: error.message)
    end

    # Enumerates what `each_entry` will yield without extracting anything: a
    # ZIP's track members come from its central directory, and a bare track
    # file, `.gz`, or `.kmz` source is a single entry. Gzip names are
    # provisional when the detected format can differ from the extension;
    # processing rewrites the entry from the real extraction.
    def each_manifest_entry(source, filename:)
      validate_source_size!(source)
      filename = utf8(filename)

      case File.extname(filename.to_s).downcase
      when *Allure::ImportFormat::EXTENSIONS
        yield ManifestEntry.new(name: File.basename(filename), index: 0)
      when ".gz"
        yield ManifestEntry.new(name: gzip_manifest_name(filename), index: 0)
      when ".kmz"
        yield ManifestEntry.new(name: File.basename(filename.to_s, ".*") + ".kml", index: 0)
      when ".zip"
        each_zip_manifest_entry(source) { yield it }
      else
        raise Error, I18n.t("workouts.batch_import.errors.unsupported_source")
      end
    rescue Zlib::Error, Zip::Error, IOError => error
      raise Error, I18n.t("workouts.batch_import.errors.malformed_archive", error: error.message)
    end

    private

    def validate_source_size!(source)
      return unless source.respond_to?(:size) && source.size > MAX_SOURCE_BYTES

      raise Error, I18n.t("workouts.batch_import.errors.source_too_large", max: "500 MB")
    end

    def each_gzip_entry(source, filename)
      rewind(source)
      with_gzip_tempfile(source) do |tempfile|
        format = detected_format!(tempfile)
        reserve_uncompressed!(tempfile.size)
        yield Entry.new(name: gzip_entry_name(filename, format, basename: true), index: 0, io: tempfile)
      end
    end

    # A KMZ is a ZIP containing KML, but it must never be sniffed as a
    # generic ZIP (that would collide with the batch path). It is a
    # single-entry source like a bare `.gpx`: the first `.kml` member is
    # extracted and yielded once. Corrupt ZIPs surface as malformed archives
    # through the `each_entry` rescue.
    def each_kmz_entry(source, filename)
      validate_directory_entries!(source)
      rewind(source)
      archive = Zip::File.open_buffer(source)
      kml_entry = archive.entries.reject(&:directory?).find do |entry|
        entry.name.to_s.downcase.end_with?(".kml")
      end
      raise Error, I18n.t("workouts.batch_import.errors.no_track_entries") unless kml_entry

      validate_entry_path!(kml_entry)
      declared_size = kml_entry.size.to_i
      compressed_size = kml_entry.compressed_size.to_i
      validate_entry_size!(declared_size, compressed_size, gzip: false)

      tempfile = Tempfile.new([ "allure-import-", ".kml" ])
      tempfile.binmode
      begin
        kml_entry.get_input_stream { |input| copy_limited(input, tempfile, MAX_ENTRY_BYTES) }
        tempfile.rewind
        reserve_uncompressed!(tempfile.size)
        yield Entry.new(name: File.basename(filename.to_s, ".*") + ".kml", index: 0, io: tempfile)
      ensure
        tempfile.close!
      end
    ensure
      archive&.close
    end

    def each_zip_entry(source)
      each_zip_candidate(source) do |entry, entry_name, format, index|
        if gzip_entry?(entry_name)
          entry.get_input_stream do |input|
            with_gzip_tempfile(input) do |tempfile|
              detected_format = detected_format!(tempfile)
              reserve_uncompressed!(tempfile.size)
              yield Entry.new(name: gzip_entry_name(entry_name, detected_format), index:, io: tempfile)
            end
          end
        else
          tempfile = Tempfile.new([ "allure-import-", format.extension ])
          tempfile.binmode
          begin
            entry.get_input_stream { |input| copy_limited(input, tempfile, MAX_ENTRY_BYTES) }
            tempfile.rewind
            reserve_uncompressed!(tempfile.size)
            yield Entry.new(name: entry_name, index:, io: tempfile)
          ensure
            tempfile.close!
          end
        end
      end
    end

    def each_zip_manifest_entry(source)
      each_zip_candidate(source) do |_entry, entry_name, format, index|
        name = gzip_entry?(entry_name) ? gzip_entry_name(entry_name, format) : entry_name
        yield ManifestEntry.new(name:, index:)
      end
    end

    # The single validation path of a ZIP's extractable track members, shared
    # by the manifest and the extraction pass so the two can never disagree
    # about which entries exist or how they are indexed.
    def each_zip_candidate(source)
      validate_directory_entries!(source)
      rewind(source)
      archive = Zip::File.open_buffer(source)
      file_entries = archive.entries.reject(&:directory?)
      if file_entries.length > MAX_ARCHIVE_ENTRIES
        raise Error, I18n.t("workouts.batch_import.errors.too_many_entries", max: MAX_ARCHIVE_ENTRIES)
      end

      total_uncompressed = 0
      index = 0
      file_entries.each do |entry|
        validate_entry_path!(entry)
        entry_name = utf8(entry.name)
        next if nested_archive?(entry_name)
        format = archive_entry_format(entry_name)
        next unless format

        declared_size = entry.size.to_i
        compressed_size = entry.compressed_size.to_i
        validate_entry_size!(declared_size, compressed_size, gzip: gzip_entry?(entry_name))
        unless gzip_entry?(entry_name)
          total_uncompressed += declared_size
          if total_uncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES
            raise Error, I18n.t("workouts.batch_import.errors.total_too_large", max: MAX_TOTAL_UNCOMPRESSED_LABEL)
          end
        end

        yield entry, entry_name, format, index
        index += 1
      end

      raise Error, I18n.t("workouts.batch_import.errors.no_track_entries") if index.zero?
    ensure
      archive&.close
    end

    def validate_directory_entries!(source, max: MAX_DIRECTORY_ENTRIES)
      count = Allure::ZipDirectory.entry_count(source)
      return if count.nil? || count <= max

      raise Error, I18n.t("workouts.batch_import.errors.too_many_entries", max:)
    end

    def validate_entry_path!(entry)
      name = utf8(entry.name)
      parts = name.split("/")
      symlink = entry.respond_to?(:ftype) && entry.ftype == :symlink
      unsafe = name.blank? || name.start_with?("/") || name.include?("\\") || parts.include?("..") || symlink
      raise Error, I18n.t("workouts.batch_import.errors.unsafe_entry", name:) if unsafe
    end

    def nested_archive?(name)
      name.to_s.downcase.match?(/\.(?:zip|tgz|tar|kmz)\z/)
    end

    def archive_entry_format(name)
      candidate = gzip_entry?(name) ? name.sub(/\.gz\z/i, "") : name
      Allure::ImportFormat.for_extension(File.extname(candidate))
    end

    def gzip_entry?(name)
      name.to_s.downcase.end_with?(".gz")
    end

    def gzip_entry_name(filename, format, basename: false)
      base = (basename ? File.basename(filename.to_s) : filename.to_s).sub(/\.gz\z/i, "")
      extension = File.extname(base)
      stem = if Allure::ImportFormat.for_extension(extension)
        base.delete_suffix(extension)
      else
        base.presence || "workout"
      end
      "#{stem}#{format.extension}"
    end

    # The `.gz` member's real name depends on the detected format, which is
    # only known after decompression; the extension-derived name is provisional
    # and processing rewrites it.
    def gzip_manifest_name(filename)
      File.basename(filename.to_s).sub(/\.gz\z/i, "").presence || "workout"
    end

    def with_gzip_tempfile(input)
      tempfile = Tempfile.new([ "allure-import-", ".tmp" ])
      tempfile.binmode
      gzip = Zlib::GzipReader.new(input)
      copy_limited(gzip, tempfile, MAX_ENTRY_BYTES)
      tempfile.rewind
      yield tempfile
    ensure
      gzip&.close
      tempfile&.close!
    end

    def detected_format!(io)
      format = Allure::ImportFormat.detect(io)
      return format if format

      raise Error, I18n.t("workouts.batch_import.errors.unsupported_source")
    end

    def validate_entry_size!(size, compressed_size, gzip: false)
      if !gzip && size > MAX_ENTRY_BYTES
        raise Error, I18n.t("workouts.import.errors.too_large", max: I18n.t("workouts.import.max_size"))
      end

      ratio = compressed_size.zero? ? Float::INFINITY : size.to_f / compressed_size
      return unless ratio > MAX_COMPRESSION_RATIO

      raise Error, I18n.t("workouts.batch_import.errors.compression_ratio")
    end

    def reserve_uncompressed!(bytes)
      @total_uncompressed_bytes += bytes
      return if @total_uncompressed_bytes <= self.class::MAX_TOTAL_UNCOMPRESSED_BYTES

      raise Error, I18n.t("workouts.batch_import.errors.total_too_large", max: self.class::MAX_TOTAL_UNCOMPRESSED_LABEL)
    end

    def copy_limited(input, output, limit)
      total = 0
      while (chunk = input.read(CHUNK_SIZE))
        total += chunk.bytesize
        if total > limit
          raise Error, I18n.t("workouts.import.errors.too_large", max: I18n.t("workouts.import.max_size"))
        end

        output.write(chunk)
      end
    end

    def rewind(io)
      io.rewind if io.respond_to?(:rewind)
    end

    def utf8(value)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
    end
  end
end
