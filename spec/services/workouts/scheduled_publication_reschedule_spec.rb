# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ScheduledPublicationReschedule do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }
  let(:publication) do
    Workouts::Publisher.new(user:, workout:, profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")).call!
  end

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    publication
  end

  it "moves the planned moment and re-enqueues the activation" do
    result = described_class.new(user:, workout:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("2_weeks")).call!

    expect(result.scheduled_for).to be_within(1.second).of(2.weeks.from_now)
    expect(publication.reload.scheduled_for).to be_within(1.second).of(2.weeks.from_now)
    expect(Workouts::ActivateScheduledPublicationJob).to have_been_enqueued.at(publication.scheduled_for)
  end

  it "refuses a delay outside the presets" do
    expect {
      described_class.new(user:, workout:, delay: 3_600).call!
    }.to raise_error(Workouts::Publisher::PublicationError)
    expect(publication.reload.scheduled_for).to be_within(1.second).of(1.day.from_now)
  end

  it "rejects a non-owner" do
    expect {
      described_class.new(user: create(:user), workout:, delay: 604_800).call!
    }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "requires a scheduled publication" do
    publication.mark_deleted!

    expect {
      described_class.new(user:, workout:, delay: 604_800).call!
    }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
