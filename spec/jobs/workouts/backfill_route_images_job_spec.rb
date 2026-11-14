# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::BackfillRouteImagesJob do
  include ActiveJob::TestHelper

  it "enqueues a render for missing or stale images only" do
    missing = create(:workout, route_image_version: 0)
    stale = create(:workout, route_image_version: Workouts::RouteImage::VERSION - 1)
    create(:workout, route_image_version: Workouts::RouteImage::VERSION)

    expect { described_class.perform_now }
      .to have_enqueued_job(Workouts::RenderRouteImageJob).with(missing)
      .and have_enqueued_job(Workouts::RenderRouteImageJob).with(stale)
    expect(Workouts::RenderRouteImageJob).to have_been_enqueued.exactly(:twice)
  end

  it "resumes from the cursor when a batch fills" do
    stub_const("Workouts::BackfillRouteImagesJob::BATCH_SIZE", 1)
    first = create(:workout, route_image_version: 0)
    create(:workout, route_image_version: 0)

    expect { described_class.perform_now(after_id: 0) }
      .to have_enqueued_job(described_class).with(after_id: first.id)
  end
end
