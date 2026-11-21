# frozen_string_literal: true

namespace :dev_tools do
  desc "Blind comparison of two summary series (ACCOUNT, IDS or LIMIT, PROMPT, OPTIONS; CALL=1 to generate)"
  task insights_compare: :environment do
    abort "Local environments only" unless Rails.env.local?
    require_relative "../dev_tools/insights_comparison"

    user = User.find_by!(username: ENV.fetch("ACCOUNT"))
    scope = user.workouts.recordings.where("analysis_version > 0")
    workouts = if ENV["IDS"].present?
      ids = ENV["IDS"].split(",").map(&:strip).uniq
      abort "Choose at most 20 workouts" if ids.size > 20
      ids.map { |id| scope.find_by_short_id!(id) }
    else
      limit = Integer(ENV.fetch("LIMIT", 8))
      abort "LIMIT must be between 1 and 20" unless (1..20).cover?(limit)
      scope.order(started_at: :desc, id: :desc).limit(limit).to_a
    end
    abort "No analysable workouts" if workouts.empty?
    workouts.each { |workout| puts "#{workout.to_param} · #{workout.title}" }
    puts "#{2 * workouts.size} generations, plus possible retries."
    next unless ENV["CALL"] == "1"

    dir = DevTools::InsightsComparison.new(workouts:).call
    puts "Read #{dir}/pairs.txt and series-A/B.txt; open diversity.txt and diagnostics.txt to reveal."
  end
end
