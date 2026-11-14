# frozen_string_literal: true

require "rails_helper"

RSpec.describe BacklogPriority do
  include ActiveJob::TestHelper

  let(:probe) do
    Class.new(ApplicationJob) do
      def self.name = "BacklogPriorityProbeJob"

      def perform(child = false)
        self.class.perform_later(true) unless child
      end
    end
  end

  before { stub_const("BacklogPriorityProbeJob", probe) }

  it "lowers the priority of what is enqueued inside, and only there" do
    described_class.enqueue { probe.perform_later(true) }
    probe.perform_later(true)

    expect(enqueued_jobs.map { it[:priority] }).to eq([ described_class::PRIORITY, nil ])
  end

  it "keeps a priority the caller chose, and restores the outer state" do
    described_class.enqueue do
      described_class.enqueue(active: false) { probe.set(priority: 3).perform_later(true) }
      expect(described_class).to be_active
    end

    expect(described_class).not_to be_active
    expect(enqueued_jobs.map { it[:priority] }).to eq([ 3 ])
  end

  it "passes the backlog priority on to what a backlog job enqueues" do
    probe.set(priority: described_class::PRIORITY).perform_now
    probe.perform_now

    expect(enqueued_jobs.map { it[:priority] }).to eq([ described_class::PRIORITY, nil ])
  end

  describe "imports" do
    let(:user) { create(:user) }
    let(:gpx) do
      ActionDispatch::Http::UploadedFile.new(tempfile: File.open(Rails.root.join("spec/fixtures/gpx/galibier.gpx")),
                                             filename: "galibier.gpx", type: "application/gpx+xml")
    end

    it "enqueues a bulk import's enrichments behind new outings" do
      Workouts::Importer.new(user:, sport: create(:sport), uploaded_file: gpx, bulk: true).call

      expect(Workouts::RenderRouteImageJob).to have_been_enqueued.at_priority(described_class::PRIORITY)
      expect(Segments::MatchWorkoutJob).to have_been_enqueued.at_priority(described_class::PRIORITY)
    end

    it "leaves a single new outing at the default priority" do
      Workouts::Importer.new(user:, sport: create(:sport), uploaded_file: gpx).call

      expect(enqueued_jobs.map { it[:priority] }.uniq).to eq([ nil ])
    end

    it "enqueues a Strava archive's work behind new outings" do
      batch = create(:workout_import_batch, user:, sport: nil, source: "strava_archive")
      batch.source_files.attach(
        io: StringIO.new(strava_archive_zip(
          "activities.csv" => strava_activities_csv([ { id: 1, name: "Galibier", type: "Ride", filename: "activities/1.gpx" } ]),
          "activities/1.gpx" => File.binread(Rails.root.join("spec/fixtures/gpx/galibier.gpx"))
        )),
        filename: "export.zip", content_type: "application/zip"
      )

      Workouts::StravaArchiveImportJob.perform_now(batch)

      expect(Workouts::RenderRouteImageJob).to have_been_enqueued.at_priority(described_class::PRIORITY)
      expect(Segments::RouteSuggestionSweepJob).to have_been_enqueued.at_priority(described_class::PRIORITY)
    end
  end
end
