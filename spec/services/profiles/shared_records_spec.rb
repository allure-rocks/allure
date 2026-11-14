# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiles::SharedRecords do
  let(:user) { create(:user, profile_records_audience: "members") }
  let(:viewer) { create(:user) }
  let(:sport) { catalog_sport("running") }

  it "does not query records without their separate opt-in" do
    user.profile_statistics_audience = "members"
    user.profile_records_audience = "none"
    expect(user).not_to receive(:records)
    expect(user).not_to receive(:effort_records)

    expect(described_class.new(user:, viewer:).call).to be_empty
  end

  it "reads private winners without their source identities, dates, or source workouts" do
    workout = create(:workout, user:, sport:, title: "Private title", distance: 5_000)
    create(:effort_record, user:, sport:, workout:)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
    groups = nil

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      groups = described_class.new(user:, viewer:).call
    end

    group = groups.sole
    expect(group.records.map(&:record_type)).to include("FD", "AP", "BP")
    expect(group.records.map(&:record_type)).not_to include("AS", "MS")
    expect(group.records.first.attributes.keys).to match_array(%w[id sport_id record_type value])
    expect(group.efforts.sole.attributes.keys).to match_array(%w[id sport_id distance_key duration_seconds])
    expect(queries).not_to include(a_string_matching(/FROM "workouts"/))
  end

  it "uses the established sport filters and standard-distance order" do
    rowing = catalog_sport("rowing")
    workout = create(:workout, user:, sport: rowing)
    create(:effort_record, user:, sport: rowing, workout:, distance_key: "km2", distance_meters: 2_000)
    create(:effort_record, user:, sport: rowing, workout:, distance_key: "m500", distance_meters: 500)

    group = described_class.new(user:, viewer:).call.sole

    expect(group.efforts.map(&:distance_key)).to eq(%w[m500 km2])
    expect(group.records.map(&:record_type)).not_to include("AS", "MS", "HA", "MC")
  end

  it "never includes another account's records" do
    create(:workout, sport:, distance: 99_000)

    expect(described_class.new(user:, viewer:).call).to be_empty
  end

  it "does not share records from a deactivated account" do
    user.deletion_scheduled_at = 7.days.from_now
    expect(user).not_to receive(:records)

    expect(described_class.new(user:, viewer:).call).to be_empty
  end

  it "does not query records outside their audience, even when statistics are shared" do
    user.profile_statistics_audience = "members"
    user.profile_records_audience = "followers"
    expect(user).not_to receive(:records)
    expect(user).not_to receive(:effort_records)

    expect(described_class.new(user:, viewer:).call).to be_empty
  end

  it "never queries records for an anonymous reader, even with the members audience" do
    expect(user).not_to receive(:records)
    expect(user).not_to receive(:effort_records)

    expect(described_class.new(user:, viewer: nil).call).to be_empty
  end
end
