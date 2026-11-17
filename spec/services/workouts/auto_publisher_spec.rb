# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Automatic publishing" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:now) { Time.zone.parse("2026-08-25 12:00:00") }
  let(:sport) { create(:sport) }
  let(:workout) { create(:workout, user:, sport:, started_at: now - 1.day) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) do
    create(:publishing_profile, :without_endpoint_masks, user:, auto_publish: true, auto_publish_acknowledged: true)
  end

  def make_ready(record = workout)
    record.update_columns(loop_reuse_version: Segments::LoopReuse::VERSION, route_image_version: Workouts::RouteImage::VERSION)
    create(:workout_toponymy, workout: record) unless record.toponymy
    record.reload
  end

  def enroll(bulk: false, at: now)
    Workouts::AutoPublicationEnrollment.new(workout:, bulk:, now: at).call
  end

  around { |example| travel_to(now) { example.run } }

  describe Workouts::AutoPublicationEnrollment do
    it "does nothing without an automatic profile" do
      create(:publishing_profile, user:)

      expect(enroll).to eq([])
      expect(workout.auto_publications).to be_empty
    end

    it "records a waiting row per automatic audience and nudges the job" do
      profile
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      rows = enroll

      expect(rows.map(&:status)).to eq([ "waiting" ])
      expect(rows.first).to have_attributes(audience: "public", publishing_profile: profile,
                                            deadline_at: now + WorkoutAutoPublication::ENRICHMENT_DEADLINE)
      expect(Workouts::AutoPublishJob).to have_been_enqueued.with(workout)
    end

    it "skips a bulk import, a stale workout and an excluded commute" do
      profile.update!(auto_publish_exclude_commute: true)

      expect(enroll(bulk: true).first).to have_attributes(status: "skipped", reason: "bulk_import", settled_at: now)

      workout.auto_publications.delete_all
      workout.update!(started_at: now - 8.days)
      expect(enroll.first).to have_attributes(status: "skipped", reason: "stale")

      workout.auto_publications.delete_all
      workout.update!(started_at: now - 1.hour, commute: true)
      expect(enroll.first).to have_attributes(status: "skipped", reason: "commute")
    end

    it "skips a workout of a sport the profile excludes, and waits for any other" do
      profile.update!(auto_publish_excluded_sports: [ sport.slug ])

      expect(enroll.first).to have_attributes(status: "skipped", reason: "sport", settled_at: now)

      workout.auto_publications.delete_all
      profile.update!(auto_publish_excluded_sports: [ catalog_sport("walking").slug ])
      expect(enroll.first).to be_waiting
    end
  end

  describe Workouts::AutoPublicationReadiness do
    it "lists every enrichment that has not settled" do
      workout.update_columns(elevation_source_requested: "dem")

      expect(described_class.new(workout).pending).to eq(%i[elevation segments places route_image])
    end

    it "counts a failed toponymy and a virtual sport as settled" do
      make_ready
      workout.toponymy.update!(status: "failed")
      expect(described_class.new(workout)).to be_ready

      workout.toponymy.update!(status: "pending")
      expect(described_class.new(workout.reload).pending).to eq([ :places ])

      workout.toponymy.destroy!
      workout.sport.update!(virtual: true)
      expect(described_class.new(workout.reload)).to be_ready
    end

    it "waits for the weather only when the waiting profile shares it (docs/dev/WEATHER.md)", :weather do
      user.update!(weather_enrichment_enabled: true)
      profile
      enroll
      make_ready
      expect(described_class.new(workout)).to be_ready

      profile.update!(settings: profile.settings.merge("weather" => true))
      expect(described_class.new(workout.reload).pending).to eq([ :weather ])

      create(:workout_weather, workout:, status: "failed")
      expect(described_class.new(workout.reload)).to be_ready
    end
  end

  describe Workouts::AutoPublisher do
    def run(at: now)
      described_class.new(workout: workout.reload, now: at).call
    end

    it "waits while an enrichment is pending" do
      profile
      enroll

      expect { run }.not_to change(WorkoutPublication, :count)
      expect(workout.auto_publications.first).to be_waiting
    end

    it "fails an overdue wait and tells the owner" do
      profile
      enroll

      run(at: now + 7.hours)

      row = workout.auto_publications.first
      expect(row).to have_attributes(status: "failed", reason: "enrichment_timeout")
      notification = user.notifications.find_by!(kind: "auto_publication_failed")
      expect(notification.subject).to eq(row)
    end

    it "publishes immediately once ready and notifies the owner" do
      profile
      enroll
      make_ready

      expect { run }.to change(WorkoutPublication, :count).by(1)

      row = workout.auto_publications.first
      expect(row).to be_published
      expect(row.workout_publication).to be_active
      expect(row.workout_publication.publishing_profile).to eq(profile)
      notification = user.notifications.find_by!(kind: "auto_published")
      expect(notification.subject).to eq(row.workout_publication)
      expect(notification.payload).not_to have_key("scheduled_for")

      expect { run }.not_to change(WorkoutPublication, :count)
    end

    it "honours the profile's safety delay" do
      profile.update!(publish_delay_seconds: PublishingProfile::PUBLISH_DELAYS.fetch("1_day"))
      enroll
      make_ready

      run

      publication = workout.auto_publications.first.workout_publication
      expect(publication).to be_scheduled
      expect(publication.scheduled_for).to be_within(1.second).of(now + 1.day)
      expect(user.notifications.find_by!(kind: "auto_published").payload["scheduled_for"]).to be_present
    end

    it "skips when the profile was turned off or the audience is already published" do
      profile
      enroll
      make_ready
      profile.update!(auto_publish: false)

      run
      expect(workout.auto_publications.first).to have_attributes(status: "skipped", reason: "profile_disabled")

      profile.update!(auto_publish: true, auto_publish_acknowledged: true)
      workout.auto_publications.delete_all
      enroll
      Workouts::Publisher.new(user:, workout:, profile:).call!

      expect { run }.not_to change(WorkoutPublication, :count)
      expect(workout.auto_publications.first).to have_attributes(status: "skipped", reason: "already_published")
    end

    it "skips a workout marked as an excluded commute after the import" do
      profile.update!(auto_publish_exclude_commute: true)
      enroll
      make_ready
      workout.update!(commute: true)

      run

      expect(workout.auto_publications.first).to have_attributes(status: "skipped", reason: "commute")
    end

    it "skips a workout whose sport the profile excludes after the import" do
      profile
      enroll
      make_ready
      profile.update!(auto_publish_excluded_sports: [ sport.slug ])

      expect { run }.not_to change(WorkoutPublication, :count)
      expect(workout.auto_publications.first).to have_attributes(status: "skipped", reason: "sport")
    end

    it "fails without publishing when the publisher refuses" do
      profile
      enroll
      make_ready
      allow_any_instance_of(Workouts::Publisher).to receive(:call!)
        .and_raise(Workouts::Publisher::PublicationError, "refused")

      run

      expect(workout.auto_publications.first).to have_attributes(status: "failed", reason: "publication_refused", detail: "refused")
      expect(user.notifications.where(kind: "auto_publication_failed").count).to eq(1)
    end
  end

  describe Workouts::AutoPublicationSweepJob do
    it "re-runs every workout with a waiting row" do
      profile
      enroll
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.perform_now

      expect(Workouts::AutoPublishJob).to have_been_enqueued.with(workout)
    end
  end

  describe Workouts::AutoPublishJob do
    it "nudges only a workout with a waiting row" do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      described_class.nudge(workout)
      expect(described_class).not_to have_been_enqueued

      profile
      enroll
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      described_class.nudge(workout)
      expect(described_class).to have_been_enqueued.with(workout)
    end
  end
end
