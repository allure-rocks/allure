# frozen_string_literal: true

require "rails_helper"

RSpec.describe SettingsHelper do
  describe "#settings_navigation_groups" do
    it "never lists connected services, which have their own area" do
      paths = helper.settings_navigation_groups.flat_map { |group| group[:items].map { it[:path] } }

      expect(paths).not_to include("/connections")
    end
  end

  describe "#time_zone_options_for" do
    it "labels Rails zones and stores their IANA identifiers" do
      expect(helper.time_zone_options_for("Europe/Paris")).to include([ "(GMT+01:00) Brussels", "Europe/Brussels" ])
    end

    it "keeps one option per identifier" do
      values = helper.time_zone_options_for("Europe/Paris").map(&:last)

      expect(values).to eq(values.uniq)
      expect(values).to all(satisfy { |value| User::TIME_ZONE_IDENTIFIERS.include?(value) })
    end

    it "keeps a stored identifier Rails does not list" do
      expect(helper.time_zone_options_for("Europe/Luxembourg").first).to eq([ "Europe/Luxembourg", "Europe/Luxembourg" ])
    end

    it "never offers an invalid value" do
      expect(helper.time_zone_options_for("Brussels").map(&:last)).not_to include("Brussels")
    end
  end
end
