# frozen_string_literal: true

namespace :workouts do
  desc "Enqueue MapLibre regeneration for every missing or stale owner route image (PLAN_DERIVATIONS.md)"
  task route_images: :environment do
    count = Workouts::BackfillRouteImagesJob.pending_scope.count
    Workouts::BackfillRouteImagesJob.perform_later
    puts "Enqueued re-render for #{count} owner route image(s). Ensure the worker is running."
  end

  desc "Force MapLibre regeneration for every persisted owner route image"
  task regenerate_route_images: :environment do
    count = 0
    Workout.joins(:route_image_attachment).find_each do |workout|
      Workouts::RenderRouteImageJob.perform_later(workout)
      count += 1
    end

    puts "Enqueued #{count} owner route image(s) for regeneration."
  end
end

namespace :segments do
  desc "Enqueue MapLibre regeneration for every missing or stale owner segment image (PLAN_DERIVATIONS.md)"
  task route_images: :environment do
    count = Segments::BackfillRouteImagesJob.pending_scope.count
    Segments::BackfillRouteImagesJob.perform_later
    puts "Enqueued re-render for #{count} owner segment image(s). Ensure the route-image worker is running."
  end

  desc "Force MapLibre regeneration for every persisted owner segment image"
  task regenerate_route_images: :environment do
    count = 0
    Segment.joins(:route_image_attachment).find_each do |segment|
      Segments::RenderRouteImageJob.perform_later(segment)
      count += 1
    end

    puts "Enqueued #{count} owner segment image(s) for regeneration."
  end
end
