# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrivacyZone do
  describe "coordinates" do
    it "builds a WGS84 point from form coordinates" do
      zone = build(:privacy_zone, center: nil, latitude: 45.071, longitude: 6.4074)

      expect(zone).to be_valid
      expect(zone.center).to be_a(RGeo::Feature::Point)
      expect([ zone.longitude, zone.latitude ]).to eq([ 6.4074, 45.071 ])
      expect(zone.to_value).to eq(
        Allure::Federation::Privacy::Zone.new(center: [ 6.4074, 45.071 ], radius_meters: 100)
      )
    end

    it "rejects coordinates outside WGS84 ranges" do
      expect(build(:privacy_zone, latitude: 91)).not_to be_valid
      expect(build(:privacy_zone, longitude: 181)).not_to be_valid
      expect(build(:privacy_zone, latitude: "not-a-number")).not_to be_valid
    end

    it "enforces the bounded radius" do
      expect(build(:privacy_zone, radius_meters: 0)).not_to be_valid
      expect(build(:privacy_zone, radius_meters: 10_001)).not_to be_valid
      expect(build(:privacy_zone, radius_meters: 100.5)).not_to be_valid
    end
  end

  describe "ownership" do
    it "scopes zones through the owning user" do
      user = create(:user)
      zone = create(:privacy_zone, user:)

      expect(user.privacy_zones).to contain_exactly(zone)
      expect(PrivacyZone.active).to contain_exactly(zone)
    end
  end

  describe "database invariants" do
    it "has a geographic GiST index" do
      index = described_class.connection.indexes(:privacy_zones).find { |candidate| candidate.columns == [ "center" ] }

      expect(index.using).to eq(:gist)
    end

    it "rejects an invalid radius below the model layer" do
      zone = create(:privacy_zone)

      expect { zone.update_column(:radius_meters, 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /privacy_zones_radius_meters/)
    end
  end
end
