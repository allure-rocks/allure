# frozen_string_literal: true

require "tempfile"
require "zip"

module Workouts
  # Opens a Strava archive (docs/dev/STRAVA-ARCHIVE.md). It reuses the generic
  # reader's guards — unsafe paths, the per-member size and compression ratio,
  # gzip members sniffed by content — but reads only what the archive names:
  # the three CSV files and one `activities/…` member at a time. The 1 000
  # member cap does not apply, since an archive holds every photo too; its
  # own bounds are the directory's declared entries, checked before opening,
  # one track file per activity at most, and the bytes extracted over the
  # whole run (docs/dev/STRAVA-ARCHIVE.md).
  #
  # The CSV files may sit at the root or under one top-level folder, when the
  # athlete unpacked the archive and zipped it again.
  class StravaArchiveReader < ArchiveReader
    MAX_CSV_BYTES = 50.megabytes
    MAX_DIRECTORY_ENTRIES = 100_000
    MAX_ACTIVITY_FILES = Allure::StravaArchive::Activities::MAX_ACTIVITIES
    MAX_TOTAL_UNCOMPRESSED_BYTES = 20.gigabytes
    MAX_TOTAL_UNCOMPRESSED_LABEL = "20 GB"
    ACTIVITIES_CSV = "activities.csv"
    ACTIVITIES_CSV_PATH = %r{\A(?:[^/]+/)?#{Regexp.escape(ACTIVITIES_CSV)}\z}
    GEAR_CSVS = { bike: "bikes.csv", shoes: "shoes.csv" }.freeze
    MEDIA_CSV = "media.csv"

    Member = Data.define(:name, :io)

    def self.open(file)
      reader = new(file)
      yield reader
    ensure
      reader&.close
    end

    def initialize(file)
      super()
      validate_archive_size!(file)
      validate_directory_entries!(file, max: MAX_DIRECTORY_ENTRIES)
      @zip = file.respond_to?(:path) && file.path ? Zip::File.open(file.path) : Zip::File.open_buffer(file)
      @root = locate_root
    rescue Zip::Error, IOError => error
      raise Error, I18n.t("workouts.batch_import.errors.malformed_archive", error: error.message)
    end

    def close = @zip&.close

    def activities
      Allure::StravaArchive::Activities.parse(read_csv!(ACTIVITIES_CSV))
    rescue Allure::StravaArchive::Activities::MalformedError => error
      raise Error, I18n.t("workouts.batch_import.errors.malformed_strava_activities", error: error.message)
    end

    def gear
      Allure::StravaArchive::Gear.parse(GEAR_CSVS.transform_values { |name| read_csv(name) })
    end

    def media_captions
      Allure::StravaArchive::MediaCaptions.parse(read_csv(MEDIA_CSV))
    end

    # Track members of `activities/` in archive order, as the names
    # `activities.csv` uses.
    def activity_files
      prefix = "#{@root}activities/"
      files = @zip.entries.filter_map do |entry|
        next if entry.directory?

        name = utf8(entry.name)
        next unless name.start_with?(prefix)

        relative = name.delete_prefix(@root)
        relative if relative.count("/") == 1 && archive_entry_format(relative)
      end
      if files.length > MAX_ACTIVITY_FILES
        raise Error, I18n.t("workouts.batch_import.errors.too_many_entries", max: MAX_ACTIVITY_FILES)
      end

      files
    end

    # Yields the decompressed member as a Member whose name carries the
    # detected format's extension, or returns nil when the archive lacks it.
    def extract(filename)
      entry = @zip.find_entry("#{@root}#{filename}")
      return nil if entry.nil? || entry.directory?

      ensure_budget_left!

      validate_entry_path!(entry)
      name = utf8(entry.name).delete_prefix(@root)
      gzip = gzip_entry?(name)
      format = archive_entry_format(name)
      raise Error, I18n.t("workouts.batch_import.errors.unsupported_source") unless format

      validate_entry_size!(entry.size.to_i, entry.compressed_size.to_i, gzip:)
      if gzip
        entry.get_input_stream do |input|
          with_gzip_tempfile(input) do |tempfile|
            reserve_uncompressed!(tempfile.size)
            yield Member.new(name: gzip_entry_name(name, detected_format!(tempfile)), io: tempfile)
          end
        end
      else
        with_member_tempfile(entry, format) { |tempfile| yield Member.new(name:, io: tempfile) }
      end
      true
    rescue Zlib::Error, Zip::Error, IOError => error
      raise Error, I18n.t("workouts.batch_import.errors.malformed_archive", error: error.message)
    end

    # Yields one `media/…` photo as a Tempfile, or returns nil when the
    # archive lacks it (slice 3). A photo over the photo cap is cut one byte
    # past it, so `Workouts::PhotoUpload` refuses it as too large.
    def extract_media(name)
      entry = @zip.find_entry("#{@root}#{name}")
      return nil if entry.nil? || entry.directory?

      ensure_budget_left!

      validate_entry_path!(entry)
      validate_entry_size!(entry.size.to_i, entry.compressed_size.to_i)
      tempfile = Tempfile.new([ "allure-strava-media-", File.extname(name) ])
      tempfile.binmode
      entry.get_input_stream { |input| IO.copy_stream(input, tempfile, Allure::Photos::Config::MAX_BYTES + 1) }
      reserve_uncompressed!(tempfile.size)
      tempfile.rewind
      yield tempfile
      true
    rescue Zlib::Error, Zip::Error, IOError => error
      raise Error, I18n.t("workouts.batch_import.errors.malformed_archive", error: error.message)
    ensure
      tempfile&.close!
    end

    private

    # Once the run has extracted its budget, nothing more is decompressed:
    # every later member is refused before it is read.
    def ensure_budget_left!
      return if @total_uncompressed_bytes < MAX_TOTAL_UNCOMPRESSED_BYTES

      raise Error, I18n.t("workouts.batch_import.errors.total_too_large", max: MAX_TOTAL_UNCOMPRESSED_LABEL)
    end

    def validate_archive_size!(file)
      return unless file.respond_to?(:size) && file.size > Allure::StravaArchive::MAX_BYTES

      raise Error, I18n.t("workouts.batch_import.errors.source_too_large", max: Allure::StravaArchive::MAX_SIZE_LABEL)
    end

    def locate_root
      candidates = @zip.entries.filter_map do |entry|
        name = utf8(entry.name)
        name.delete_suffix(ACTIVITIES_CSV) if !entry.directory? && name.match?(ACTIVITIES_CSV_PATH)
      end
      raise Error, I18n.t("workouts.batch_import.errors.not_strava_archive") if candidates.empty?

      candidates.min_by(&:length)
    end

    def read_csv!(name)
      read_csv(name) || raise(Error, I18n.t("workouts.batch_import.errors.not_strava_archive"))
    end

    def read_csv(name)
      entry = @zip.find_entry("#{@root}#{name}")
      return nil if entry.nil? || entry.directory?

      validate_entry_path!(entry)
      if entry.size.to_i > MAX_CSV_BYTES
        raise Error, I18n.t("workouts.import.errors.too_large", max: I18n.t("workouts.import.max_size"))
      end

      output = StringIO.new(+"")
      entry.get_input_stream { |input| copy_limited(input, output, MAX_CSV_BYTES) }
      reserve_uncompressed!(output.string.bytesize)
      output.string
    end

    def with_member_tempfile(entry, format)
      tempfile = Tempfile.new([ "allure-strava-", format.extension ])
      tempfile.binmode
      entry.get_input_stream { |input| copy_limited(input, tempfile, MAX_ENTRY_BYTES) }
      reserve_uncompressed!(tempfile.size)
      tempfile.rewind
      yield tempfile
    ensure
      tempfile&.close!
    end
  end
end
