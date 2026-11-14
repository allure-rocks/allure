# frozen_string_literal: true

namespace :best_efforts do
  desc "Enqueue a best-effort rebuild for every workout (resume with AFTER_ID=…, narrow with SPORT=slug)"
  task backfill: :environment do
    after_id = Integer(ENV.fetch("AFTER_ID", "0"), exception: false)
    abort "AFTER_ID must be a non-negative integer." if after_id.nil? || after_id.negative?

    sport_slug = ENV["SPORT"].to_s.strip.presence
    BestEfforts::BackfillJob.perform_later(after_id:, sport_slug:)
    scope = sport_slug ? "for sport #{sport_slug} " : ""
    puts "Enqueued BestEfforts::BackfillJob from workout id > #{after_id} #{scope}(ensure the worker is running)."
  end

  desc "Rebuild best efforts for one workout now (WORKOUT=short id or numeric id)"
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

    BestEfforts::Rebuild.new(workout:).call
    Records::RecomputeService.new(user: workout.user, sport: workout.sport).call
    puts "Rebuilt #{workout.best_efforts.count} best effort(s) for workout #{identifier}."
  rescue ActiveRecord::RecordNotFound
    abort "No workout found for #{identifier}."
  end
end
