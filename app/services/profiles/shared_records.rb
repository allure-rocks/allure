# frozen_string_literal: true

module Profiles
  # The existing personal winners, shared independently from the journal and
  # the volume totals. Project only the fields needed by the record helpers:
  # neither source workout nor achievement date is even loaded for this card.
  class SharedRecords
    Group = Data.define(:sport, :records, :efforts)

    def initialize(user:, viewer:)
      @user = user
      @policy = SharingPolicy.new(user:, viewer:)
    end

    def call
      return [] unless @policy.allowed?(audience: @user.profile_records_audience)

      records = @user.records.select(:id, :sport_id, :record_type, :value).includes(:sport)
        .select { |record| Record.visible_type?(record.record_type, record.sport) }
        .group_by(&:sport)
      efforts = @user.effort_records.select(:id, :sport_id, :distance_key, :duration_seconds).includes(:sport).group_by(&:sport)

      (records.keys | efforts.keys).sort_by(&:position).map do |sport|
        Group.new(sport:, records: records.fetch(sport, []).sort_by { |record| Record::TYPES.index(record.record_type) },
                  efforts: ordered_efforts(sport, efforts.fetch(sport, [])))
      end
    end

    private

    def ordered_efforts(sport, efforts)
      profile = Allure::Gpx::BestEfforts.profile_for(sport.slug)
      order = profile ? Allure::Gpx::BestEfforts::PROFILES.fetch(profile) : []
      efforts.sort_by { |record| order.index(record.distance_key) || order.length }
    end
  end
end
