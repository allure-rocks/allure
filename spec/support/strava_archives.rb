# frozen_string_literal: true

require "csv"
require "zip"
require "zlib"

# Synthetic Strava archives (docs/dev/STRAVA-ARCHIVE.md): the leading columns of
# `activities.csv` in the current, legacy (no private note) and localized
# layouts, plus a few appended columns the reader must ignore. No real athlete
# data is ever committed.
module StravaArchiveHelpers
  HEADERS = {
    en: [ "Activity ID", "Activity Date", "Activity Name", "Activity Type", "Activity Description",
          "Elapsed Time", "Distance", "Max Heart Rate", "Relative Effort", "Commute",
          "Activity Private Note", "Activity Gear", "Filename", "Athlete Weight", "Bike Weight",
          "Elapsed Time", "Moving Time", "Distance", "Commute", "Media" ],
    de: [ "Aktivitäts-ID", "Aktivitätsdatum", "Name der Aktivität", "Aktivitätsart", "Aktivitätsbeschreibung",
          "Verstrichene Zeit", "Distanz", "Max. Herzfrequenz", "Relative Leistung", "Pendeln",
          "Hinweis zur Privatsphäre für Aktivitäten", "Aktivitätsausrüstung", "Dateiname", "Sportlergewicht",
          "Fahrradgewicht", "Verstrichene Zeit", "Bewegungszeit", "Distanz", "Pendeln", "Medien" ]
  }.freeze

  # rows: hashes with :id, :name, :type, :description, :note, :commute, :gear, :filename, :date,
  # :media (the last column, `|`-separated)
  def strava_activities_csv(rows, language: :en, legacy: false)
    header = HEADERS.fetch(language).dup
    header.delete_at(10) if legacy
    CSV.generate do |csv|
      csv << header
      rows.each do |row|
        values = [
          row.fetch(:id).to_s, row.fetch(:date, "Jun 1, 2026, 8:00:00 AM"), row[:name], row[:type],
          row[:description], "3600", "10.0", "", "", row.fetch(:commute, false).to_s,
          row[:note], row[:gear], row[:filename], "70.0", "", "3600.0", "3500.0", "10000.0", "0.0", row[:media]
        ]
        values.delete_at(10) if legacy
        csv << values
      end
    end
  end

  def strava_archive_zip(files)
    Zip::OutputStream.write_buffer do |zip|
      files.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end.string
  end

  def strava_gzip(content)
    buffer = StringIO.new
    Zlib::GzipWriter.wrap(buffer) { |gzip| gzip.write(content) }
    buffer.string
  end
end

RSpec.configure do |config|
  config.include StravaArchiveHelpers
end
