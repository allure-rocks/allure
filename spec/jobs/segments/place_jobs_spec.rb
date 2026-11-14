# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Segment place jobs" do
  include ActiveJob::TestHelper

  around do |example|
    original = ENV["GEOCODING_BASE_URL"]
    ENV["GEOCODING_BASE_URL"] = "https://geocoding.test"
    example.run
  ensure
    ENV["GEOCODING_BASE_URL"] = original
  end

  it "geocodes a new course once it is committed" do
    segment = create(:segment)

    expect(Segments::GeocodePlaceJob).to have_been_enqueued.with(segment)
  end

  describe Segments::GeocodePlaceJob do
    it "names the course through the provider" do
      segment = create(:segment)
      stub_request(:get, %r{\Ahttps://geocoding\.test/reverse})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: { name: "Vaujany", addresstype: "village", address: { village: "Vaujany" } }.to_json)

      described_class.perform_now(segment)

      expect(segment.reload).to have_attributes(place_name: "Vaujany", place_status: "ready")
    end

    it "marks the course failed once the provider keeps failing" do
      segment = create(:segment)
      stub_request(:get, %r{\Ahttps://geocoding\.test/reverse}).to_return(status: 503)

      perform_enqueued_jobs do
        described_class.perform_later(segment)
      rescue Allure::Toponyms::Nominatim::UnavailableError
        nil
      end

      expect(segment.reload.place_status).to eq("failed")
    end
  end

  describe Segments::BackfillPlacesJob do
    it "geocodes pending and failed courses in resumable batches" do
      stub_const("Segments::BackfillPlacesJob::BATCH_SIZE", 2)
      first = create(:segment, place_status: "pending")
      second = create(:segment, place_status: "failed")
      create(:segment, place_status: "ready", place_name: "Rochelune")
      create(:segment, place_status: "unavailable")
      clear_enqueued_jobs

      described_class.perform_now

      expect(Segments::GeocodePlaceJob).to have_been_enqueued.with(first, force: true)
      expect(Segments::GeocodePlaceJob).to have_been_enqueued.with(second, force: true)
      expect(described_class).to have_been_enqueued.with(after_id: second.id)
    end
  end

  describe Segments::PlaceRecoveryJob do
    it "retries a lost or recently failed course, never an old one" do
      now = Time.current
      lost = create(:segment, place_status: "pending", created_at: now - 3.hours)
      failed = create(:segment, place_status: "failed", place_geocoded_at: now - 7.hours, created_at: now - 1.day)
      create(:segment, place_status: "pending", created_at: now - 10.minutes)
      create(:segment, place_status: "pending", created_at: now - 10.days)
      create(:segment, place_status: "failed", place_geocoded_at: now - 1.hour, created_at: now - 1.day)
      clear_enqueued_jobs

      described_class.perform_now

      expect(Segments::GeocodePlaceJob).to have_been_enqueued.exactly(2).times
      expect(Segments::GeocodePlaceJob).to have_been_enqueued.with(lost, force: true)
      expect(Segments::GeocodePlaceJob).to have_been_enqueued.with(failed, force: true)
    end
  end
end
