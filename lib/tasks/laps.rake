# frozen_string_literal: true

namespace :laps do
  desc "Enqueue a detected-lap rebuild for every workout (resume with AFTER_ID=…)"
  task backfill: :environment do
    after_id = Integer(ENV.fetch("AFTER_ID", "0"), exception: false)
    abort "AFTER_ID must be a non-negative integer." if after_id.nil? || after_id.negative?

    Laps::BackfillJob.perform_later(after_id:)
    puts "Enqueued Laps::BackfillJob from workout id > #{after_id}. Ensure the worker is running."
  end

  desc "Rebuild detected laps for one workout now (WORKOUT=short id or numeric id)"
  task rebuild: :environment do
    identifier = ENV["WORKOUT"].to_s.strip
    abort "WORKOUT is required (set WORKOUT=<short id or numeric id>)." if identifier.empty?

    workout =
      if identifier.match?(/\A\d+\z/)
        Workout.find_by(id: identifier)
      else
        Workout.find_by_short_id!(identifier)
      end
    abort "No workout found for #{identifier}." unless workout

    Laps::Rebuild.new(workout:).call
    puts "Rebuilt #{workout.detected_laps.count} detected lap(s) for workout #{identifier}."
  rescue ActiveRecord::RecordNotFound
    abort "No workout found for #{identifier}."
  end
end
