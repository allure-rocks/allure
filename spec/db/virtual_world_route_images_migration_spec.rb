# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261107120000_rerender_virtual_world_route_images").to_s

RSpec.describe RerenderVirtualWorldRouteImages do
  include ActiveJob::TestHelper

  let(:virtual_sport) { catalog_sport("cycling_virtual") }
  let(:road_sport) { catalog_sport("cycling_road") }

  def migrate
    migration = described_class.new
    migration.suppress_messages { migration.migrate(:up) }
  end

  def workout_at(longitude, latitude, sport: virtual_sport, **attributes)
    point = RGeo::Geographic.spherical_factory(srid: 4326).point(longitude, latitude)
    create(:workout, sport:, start_point: point, bounds: [ latitude, longitude, latitude, longitude ],
      route_image_version: Workouts::RouteImage::VERSION, **attributes)
  end

  it "invalidates the recordings drawn on the two worlds whose map changed and queues one low-priority sweep" do
    watopia = workout_at(166.95251, -11.63555)
    paris = workout_at(2.31415, 48.867625)
    richmond = workout_at(-77.44177, 37.5394)
    real_ride = workout_at(166.95251, -11.63555, sport: road_sport)
    indoor = create(:workout, :unpositioned, sport: virtual_sport, route_image_version: Workouts::RouteImage::VERSION)
    manual = create(:workout, :manual, sport: virtual_sport, route_image_version: Workouts::RouteImage::VERSION)
    credit = create(:workout, :credit, credited_from: watopia, sport: virtual_sport,
      route_image_version: Workouts::RouteImage::VERSION)

    expect { migrate }.to have_enqueued_job(Workouts::BackfillRouteImagesJob)
      .with(no_args).at_priority(BacklogPriority::PRIORITY).exactly(:once)

    expect([ watopia, paris ].map { |workout| workout.reload.route_image_version }).to eq([ 0, 0 ])
    expect([ richmond, real_ride, indoor, manual, credit ].map { |workout| workout.reload.route_image_version })
      .to eq([ Workouts::RouteImage::VERSION ] * 5)
  end

  it "does not enqueue anything on a fresh installation or with only other worlds" do
    expect { migrate }.not_to have_enqueued_job(Workouts::BackfillRouteImagesJob)
    workout_at(-77.44177, 37.5394)

    expect { migrate }.not_to have_enqueued_job(Workouts::BackfillRouteImagesJob)
  end

  it "fails visibly when enqueueing is aborted and can be retried without losing the pending work" do
    workout = workout_at(166.95251, -11.63555)
    configured = instance_double(ActiveJob::ConfiguredJob, perform_later: false)
    allow(Workouts::BackfillRouteImagesJob).to receive(:set).and_return(configured)

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /retry the migration/)
    expect(workout.reload.route_image_version).to eq(0)

    allow(Workouts::BackfillRouteImagesJob).to receive(:set).and_call_original
    expect { migrate }.to have_enqueued_job(Workouts::BackfillRouteImagesJob)
  end
end
