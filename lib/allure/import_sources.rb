# frozen_string_literal: true

module Allure
  # The registry of workout import sources. A source declares where entries
  # come from; the import page renders one panel per source, and the batch job
  # keeps owning discovery, progress, deduplication, and cancellation.
  #
  # `kind` is `:file` (uploaded archives), `:device` (browser-side download,
  # no server credentials), `:remote` (server-side provider with a stored
  # connection, docs/dev/REMOTE-IMPORTS.md), `:archive` (one uploaded export of
  # another service, read with its metadata and submitted from its own panel,
  # PLAN_STRAVA_ARCHIVE.md), or `:manual` (a workout typed in by hand, with no
  # file and its own form, docs/dev/MANUAL-ENTRY.md). A remote source exists for an
  # account only while the operator enables it.
  module ImportSources
    Source = Data.define(:key, :kind, :icon) do
      def file? = kind == :file
      def device? = kind == :device
      def remote? = kind == :remote
      def archive? = kind == :archive
      def manual? = kind == :manual
    end

    FILE = Source.new(key: "file", kind: :file, icon: "file-upload")
    STRAVA_ARCHIVE = Source.new(key: "strava_archive", kind: :archive, icon: "brand-strava")
    IGPSPORT_DEVICE = Source.new(key: "igpsport_device", kind: :device, icon: "bluetooth")
    GARMIN_CONNECT = Source.new(key: "garmin_connect", kind: :remote, icon: "device-watch")
    EXR = Source.new(key: "exr", kind: :remote, icon: "kayak")
    WITHINGS = Source.new(key: "withings", kind: :remote, icon: "device-heart-monitor")
    ZWIFT = Source.new(key: "zwift", kind: :remote, icon: "brand-zwift")
    MANUAL = Source.new(key: "manual", kind: :manual, icon: "pencil")

    ALL = [ FILE, STRAVA_ARCHIVE, IGPSPORT_DEVICE, GARMIN_CONNECT, EXR, WITHINGS, ZWIFT, MANUAL ].freeze
    KINDS = %i[file device remote archive manual].freeze

    module_function

    def all = ALL

    def for(key) = ALL.find { |source| source.key == key.to_s }

    # The sources the import page and the settings offer: every local source,
    # and the remote ones the operator enabled.
    def enabled = ALL.select { |source| !source.remote? || RemoteImports::Config.enabled?(source.key) }

    def remote = ALL.select(&:remote?)
  end
end
