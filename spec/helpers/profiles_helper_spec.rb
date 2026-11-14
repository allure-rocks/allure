# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfilesHelper do
  let(:user) { build(:user, username: "rider", unit_system: "metric") }

  before do
    viewer = user
    helper.define_singleton_method(:current_user) { viewer }
    assign(:profile_account, user)
  end

  it "reuses the sport-mix payload with publication counts only and the current journal period" do
    sports = %w[cycling running walking hiking rowing trail fitness]
    entries = sports.map.with_index do |slug, index|
      Profiles::Journal::SportEntry.new(key: slug, value: slug, sport: build(:sport, slug:), count: 7 - index)
    end
    assign(:journal, instance_double(Profiles::Journal, selector_sports: entries, period: "year", selected_sport: nil))

    payload = helper.profile_sport_mix_payload

    expect(payload[:slices].size).to eq(6)
    expect(payload[:slices].sum { |slice| slice[:values][:workouts] }).to eq(28)
    expect(payload[:slices].flat_map { |slice| slice[:values].keys }.uniq).to eq([ :workouts ])
    expect(payload[:slices].first[:url]).to eq("/@rider?period=year&sport=cycling")
    expect(payload[:slices].last).to include(name: I18n.t("me.mix.others"), values: { workouts: 3 }, url: nil)
  end

  it "keeps remote filter links on the local cached profile" do
    actor = build(:actor, acct: "demo@remote.example", handle: "demo@remote.example")
    assign(:profile_account, actor)
    assign(:journal, instance_double(Profiles::Journal, period: "all", selected_sport: nil))

    url = helper.profile_journal_path(sport: 'label:Unusual "sport" <test>')

    expect(url).to start_with("#{helper.remote_profile_path(actor.acct)}?")
    expect(URI.parse(url).host).to be_nil
    expect(Rack::Utils.parse_nested_query(URI.parse(url).query)).to eq("sport" => 'label:Unusual "sport" <test>')
  end

  describe "shared statistics chart" do
    let(:cycling) { build(:sport, slug: "cycling") }
    let(:rowing) { build(:sport, slug: "rowing", records_elevation: false) }
    let(:rows) do
      [
        Profiles::SharedStatistics::Row.new(sport: cycling, total_workouts: 12, total_distance: 12_345,
                                          total_duration: 3_660, total_ascent: 0),
        Profiles::SharedStatistics::Row.new(sport: rowing, total_workouts: 3, total_distance: 5_000,
                                          total_duration: 1_800, total_ascent: nil)
      ]
    end

    it "embeds only real totals and formatted values in the existing sport order" do
      payload = helper.profile_statistics_payload(rows, :total_distance)

      expect(payload.keys).to match_array(%i[entries maximum])
      expect(payload[:entries].map { |entry| entry[:name] }).to eq(rows.map { |row| helper.sport_display_name(row.sport) })
      expect(payload[:entries].map { |entry| entry[:value] }).to eq([ 12_345, 5_000 ])
      expect(payload[:entries].first.keys).to match_array(%i[name value formatted])
      expect(payload[:entries].first[:formatted]).to eq("12,35 km")
      expect(payload[:maximum]).to eq("12,35 km")
    end

    it "omits inapplicable sport values without changing a genuine zero" do
      payload = helper.profile_statistics_payload(rows, :total_ascent)

      expect(payload[:entries]).to eq([ { name: helper.sport_display_name(cycling), value: 0, formatted: "0 m" } ])
      expect(payload[:maximum]).to eq("0 m")
    end

    it "omits unavailable measures and refuses any statistic outside the whitelist" do
      duration_only = [ rows.first.with(total_distance: nil, total_ascent: nil) ]

      expect(helper.profile_statistics_metrics(duration_only)).to eq(%i[total_workouts total_duration])
      expect { helper.profile_statistics_payload(rows, :average_heart_rate) }.to raise_error(ArgumentError)
    end

    it "keeps SI values unchanged while formatting in the reader's units" do
      user.unit_system = "imperial"

      payload = helper.profile_statistics_payload(rows, :total_distance)

      expect(payload[:entries].first[:value]).to eq(12_345)
      expect(payload[:entries].first[:formatted]).to include("mi")
      expect(payload[:maximum]).to include("mi")
    end
  end
end
