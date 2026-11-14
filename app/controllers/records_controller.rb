# frozen_string_literal: true

# The current user's personal records, grouped by sport. Owner-only: there is
# no :id route, so another user's records are never addressable (a signed-out
# viewer is redirected to sign in by authentication, not 404).
#
# The page shows one sport at a time (DESIGN.md §20.8). Sports are ordered most
# practised first, so it opens on the account's main sport; `?sport_id=` names
# the one to show, which the hub's filtered "Voir les records" link uses. A
# sport whose records outlive their workouts keeps its group, after the
# practised ones.
class RecordsController < ApplicationController
  def index
    records = Record.where(user: current_user).includes(:sport, :workout).to_a
    effort_records = EffortRecord.where(user: current_user).includes(:sport, :workout).to_a

    @records_by_sport = records
      .select { |record| Record.visible_type?(record.record_type, record.sport) }
      .group_by(&:sport)
      .transform_values { |rows| rows.sort_by { |record| Record::TYPES.index(record.record_type) } }
    @effort_records_by_sport = effort_records.group_by(&:sport).transform_values { |rows| ordered_efforts(rows) }
    @sports = (@records_by_sport.keys | @effort_records_by_sport.keys)
      .sort_by { |sport| [ -practised_counts.fetch(sport.id, 0), sport.position ] }
    @selected_sport = @sports.find { |sport| sport.id.to_s == params[:sport_id].to_s } || @sports.first
  end

  private

  # The account's activity count per sport, the same ranking the workout list's
  # sport pills use (DESIGN.md §10.6).
  def practised_counts
    @practised_counts ||= current_user.workouts.group(:sport_id).count
  end

  # Standard distances list in course order, not by performance.
  def ordered_efforts(effort_records)
    sport = effort_records.first.sport
    profile = Allure::Gpx::BestEfforts.profile_for(sport.slug)
    order = profile ? Allure::Gpx::BestEfforts::PROFILES.fetch(profile) : []
    effort_records.sort_by { |record| order.index(record.distance_key) || order.length }
  end
end
