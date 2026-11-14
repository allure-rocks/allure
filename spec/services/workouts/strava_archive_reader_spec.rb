# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::StravaArchiveReader do
  let(:gpx) { Rails.root.join("spec/fixtures/gpx/galibier.gpx").binread }

  def archive_file(content)
    file = Tempfile.new([ "strava-reader-", ".zip" ])
    file.binmode
    file.write(content)
    file.rewind
    file
  end

  def csv(rows) = strava_activities_csv(rows)

  it "refuses an archive whose directory declares too many entries before opening it" do
    file = archive_file(zip_declaring(200_000))
    expect(Zip::File).not_to receive(:open)
    expect(Zip::File).not_to receive(:open_buffer)

    expect { described_class.open(file) { nil } }
      .to raise_error(Workouts::ArchiveReader::Error, /trop d'entrées \(maximum : 100000\)/)
  ensure
    file&.close!
  end

  it "refuses more track files than an archive holds activities" do
    members = { "activities.csv" => csv([ { id: 1, name: "Sortie" } ]) }
    (described_class::MAX_ACTIVITY_FILES + 1).times { |index| members["activities/#{index}.gpx"] = "x" }
    file = archive_file(strava_archive_zip(members))

    described_class.open(file) do |reader|
      expect { reader.activity_files }
        .to raise_error(Workouts::ArchiveReader::Error, /trop d'entrées \(maximum : 10000\)/)
    end
  ensure
    file&.close!
  end

  it "stops decompressing once the run has extracted its budget" do
    stub_const("#{described_class}::MAX_TOTAL_UNCOMPRESSED_BYTES", gpx.bytesize + 1)
    file = archive_file(strava_archive_zip(
      "activities.csv" => csv([ { id: 1, filename: "activities/1.gpx" } ]),
      "activities/1.gpx" => gpx, "activities/2.gpx" => gpx, "activities/3.gpx" => gpx
    ))

    described_class.open(file) do |reader|
      expect(reader.extract("activities/1.gpx") { nil }).to be(true)
      expect { reader.extract("activities/2.gpx") { nil } }
        .to raise_error(Workouts::ArchiveReader::Error, /trop de données décompressées \(maximum : 20 GB\)/)

      # Spent: the next member is refused before a byte of it is read.
      expect_any_instance_of(Zip::Entry).not_to receive(:get_input_stream) # rubocop:disable RSpec/AnyInstance
      expect { reader.extract("activities/3.gpx") { nil } }.to raise_error(Workouts::ArchiveReader::Error)
      expect { reader.extract_media("activities/3.gpx") { nil } }.to raise_error(Workouts::ArchiveReader::Error)
    end
  ensure
    file&.close!
  end
end
