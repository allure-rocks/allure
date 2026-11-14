# frozen_string_literal: true

namespace :segments do
  desc "Update loop detection on positioned recordings and reuse existing loops (resume with AFTER_ID=…)"
  task loop_reuse: :environment do
    after_id = Integer(ENV.fetch("AFTER_ID", "0"), exception: false)
    abort "AFTER_ID must be a non-negative integer." if after_id.nil? || after_id.negative?

    count = Segments::BackfillLoopReuseJob.pending_scope.where("workouts.id > ?", after_id).count
    Segments::BackfillLoopReuseJob.perform_later(after_id:)
    puts "Enqueued Segments::BackfillLoopReuseJob for #{count} workout(s) from id > #{after_id}. " \
         "Ensure the worker is running."
  end

  desc "Build the stored elevation profile of source-backed segments (resume with AFTER_ID=…)"
  task elevation_profiles: :environment do
    after_id = Integer(ENV.fetch("AFTER_ID", "0"), exception: false)
    abort "AFTER_ID must be a non-negative integer." if after_id.nil? || after_id.negative?

    count = Segments::BackfillElevationProfilesJob.pending_scope.where("segments.id > ?", after_id).count
    Segments::BackfillElevationProfilesJob.perform_later(after_id:)
    puts "Enqueued Segments::BackfillElevationProfilesJob for #{count} segment(s) from id > #{after_id}. " \
         "Ensure the worker is running."
  end

  desc "Give eligible segments the terrain service's elevation (resume with AFTER_ID=…)"
  task terrain_elevation: :environment do
    abort "ELEVATION_BASE_URL is not set." unless Allure::Elevation::Config.configured?

    after_id = Integer(ENV.fetch("AFTER_ID", "0"), exception: false)
    abort "AFTER_ID must be a non-negative integer." if after_id.nil? || after_id.negative?

    count = Segments::BackfillTerrainElevationJob.pending_scope.where("segments.id > ?", after_id).count
    Segments::BackfillTerrainElevationJob.perform_later(after_id:)
    puts "Enqueued Segments::BackfillTerrainElevationJob for #{count} segment(s) from id > #{after_id}. " \
         "Ensure the worker is running."
  end

  desc "Geocode the nearby place of pending or failed segments (resume with AFTER_ID=…)"
  task places: :environment do
    abort "GEOCODING_BASE_URL is not set." unless Allure::Toponyms::Config.configured?

    after_id = Integer(ENV.fetch("AFTER_ID", "0"), exception: false)
    abort "AFTER_ID must be a non-negative integer." if after_id.nil? || after_id.negative?

    count = Segments::BackfillPlacesJob.pending_scope.where("segments.id > ?", after_id).count
    Segments::BackfillPlacesJob.perform_later(after_id:)
    puts "Enqueued Segments::BackfillPlacesJob for #{count} segment(s) from id > #{after_id}. " \
         "Ensure the worker is running."
  end
end
