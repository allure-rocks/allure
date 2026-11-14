# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::BackfillRouteImagesJob do
  include ActiveJob::TestHelper

  it "enqueues a render for missing or stale images only" do
    missing = create(:segment, route_image_version: 0)
    create(:segment, route_image_version: Segments::RouteImage::VERSION)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.perform_now }
      .to have_enqueued_job(Segments::RenderRouteImageJob).with(missing)
    expect(Segments::RenderRouteImageJob).to have_been_enqueued.exactly(:once)
  end

  it "resumes from the cursor when a batch fills" do
    stub_const("Segments::BackfillRouteImagesJob::BATCH_SIZE", 1)
    first = create(:segment, route_image_version: 0)
    create(:segment, route_image_version: 0)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.perform_now(after_id: 0) }
      .to have_enqueued_job(described_class).with(after_id: first.id)
  end
end
