# frozen_string_literal: true

namespace :workouts do
  desc "Enqueue the rebuild sweep for workouts with stale facts or analysis (resume with AFTER_ID=…)"
  task rebuild: :environment do
    after_id = Integer(ENV.fetch("AFTER_ID", "0"), exception: false)
    abort "AFTER_ID must be a non-negative integer." if after_id.nil? || after_id.negative?

    Workouts::BackfillRebuildJob.perform_later(after_id:)
    puts "Enqueued Workouts::BackfillRebuildJob from workout id > #{after_id}. Ensure the worker is running."
  end

  desc "Enqueue the geocoding sweep for missing or outdated toponymies (resume with AFTER_ID=…)"
  task toponymy: :environment do
    after_id = Integer(ENV.fetch("AFTER_ID", "0"), exception: false)
    abort "AFTER_ID must be a non-negative integer." if after_id.nil? || after_id.negative?

    Workouts::BackfillToponymyJob.perform_later(after_id:)
    puts "Enqueued Workouts::BackfillToponymyJob from workout id > #{after_id}. Ensure the worker is running."
  end

  desc "Enqueue the heart-rate histogram sweep for recordings with a missing or outdated histogram (resume with AFTER_ID=…)"
  task heart_rate: :environment do
    after_id = Integer(ENV.fetch("AFTER_ID", "0"), exception: false)
    abort "AFTER_ID must be a non-negative integer." if after_id.nil? || after_id.negative?

    HeartRates::BackfillJob.perform_later(after_id:)
    puts "Enqueued HeartRates::BackfillJob from workout id > #{after_id}. Ensure the worker is running."
  end
end
