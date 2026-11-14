# frozen_string_literal: true

module Allure
  # Curated, bilingual release notes read from config/release_notes.yml.
  #
  # This is editorial content rather than UI copy: it changes at each release
  # and is maintained next to CHANGELOG.md and config/version.rb, so it lives
  # in its own data file instead of the locale files. The version constant is
  # the trigger — notes exist only when a release adds them.
  #
  # Missing or malformed data fails closed: no notes, no dialog, no exception.
  # A release with no notes is legitimate, and an instance booting a build
  # whose notes file was rolled back must still serve every page.
  module ReleaseNotes
    PATH = Rails.root.join("config/release_notes.yml")

    class << self
      # Entries for one version in the requested locale, falling back to
      # English (the application's full fallback) and then to an empty list.
      def for(version:, locale: I18n.locale)
        strings = data.dig(locale.to_s, version.to_s) || data.dig("en", version.to_s)
        Array(strings).filter_map { |entry| entry.to_s.strip.presence }
      end

      def reset!
        @data = nil
      end

      private

      def data
        @data ||= YAML.safe_load_file(PATH, aliases: false) || {}
      rescue Errno::ENOENT, Psych::Exception
        {}
      end
    end
  end
end
