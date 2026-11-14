# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Fit::SportCatalog do
  # Resolves the emitted alias the same way an import does, so these
  # expectations cover the real detection path rather than the lookup table
  # in isolation.
  def slug_for(sport:, sub_sport: nil)
    value = described_class.alias_for(sport:, sub_sport:)
    return nil if value.nil?

    track = Allure::Gpx::Track.new(
      segments: [],
      activity_signals: [ Allure::Gpx::ActivitySignal.new(source: :fit_sport, value:) ]
    )
    Allure::ActivityDetector.new.detect(track)&.sport_slug
  end

  describe "every emitted alias" do
    let(:known_aliases) do
      Allure::ActivityTypeCatalog::SPORT_ALIASES.values.flatten.map(&:downcase).to_set
    end

    # A typo here would not raise; it would silently stop detecting a sport
    # and fall back for every file recorded with it.
    it "exists in the shared activity type catalog" do
      emitted = (described_class::SUB_SPORT_ALIASES.values + described_class::SPORT_ALIASES.values).uniq

      expect(emitted.reject { known_aliases.include?(it.downcase) }).to be_empty
    end

    it "resolves to a sport rather than being dropped as ambiguous" do
      emitted = (described_class::SUB_SPORT_ALIASES.keys.map { { sport: it.first, sub_sport: it.last } } +
                 described_class::SPORT_ALIASES.keys.map { { sport: it } })

      unresolved = emitted.reject { slug_for(**it) }

      expect(unresolved).to be_empty
    end
  end

  describe "sub sport disambiguation" do
    {
      %i[running trail] => "trail",
      %i[running street] => "running",
      %i[running treadmill] => "running_virtual",
      %i[running indoor_running] => "running_virtual",
      %i[running virtual_activity] => "running_virtual",
      %i[cycling road] => "cycling_road",
      %i[cycling mountain] => "mountain_biking",
      %i[cycling downhill] => "mountain_biking",
      %i[cycling gravel_cycling] => "cycling_gravel",
      %i[cycling mixed_surface] => "cycling_gravel",
      %i[cycling e_bike_mountain] => "mountain_biking_electric",
      %i[cycling e_bike_fitness] => "cycling_electric",
      %i[cycling indoor_cycling] => "cycling_virtual",
      %i[cycling spin] => "cycling_virtual",
      %i[cycling virtual_activity] => "cycling_virtual",
      %i[e_biking e_bike_mountain] => "mountain_biking_electric",
      %i[fitness_equipment indoor_rowing] => "rowing_virtual",
      %i[fitness_equipment indoor_cycling] => "cycling_virtual",
      %i[fitness_equipment elliptical] => "fitness",
      %i[fitness_equipment stair_climbing] => "fitness",
      %i[training strength_training] => "strength_training",
      %i[training cardio_training] => "fitness",
      %i[training hiit] => "fitness",
      %i[training flexibility_training] => "fitness",
      %i[training yoga] => "fitness",
      %i[training pilates] => "fitness",
      %i[rowing indoor_rowing] => "rowing_virtual",
      %i[alpine_skiing backcountry] => "skiing_touring",
      %i[swimming lap_swimming] => "pool_swimming",
      %i[swimming open_water] => "open_water_swimming",
      # A hike on a trail is a hike, not a trail run.
      %i[hiking trail] => "hiking"
    }.each do |(sport, sub_sport), slug|
      it "maps #{sport}/#{sub_sport} to #{slug}" do
        expect(slug_for(sport:, sub_sport:)).to eq(slug)
      end
    end
  end

  describe "commute sub sport" do
    it "flags a commuting cycling activity without changing its sport" do
      expect(slug_for(sport: :cycling, sub_sport: :commuting)).to eq("cycling")
      expect(described_class.commute?(sport: :cycling, sub_sport: :commuting)).to be(true)
      expect(described_class.commute?(sport: :e_biking, sub_sport: :commuting)).to be(true)
    end

    it "does not flag other pairs" do
      expect(described_class.commute?(sport: :cycling, sub_sport: :road)).to be(false)
      expect(described_class.commute?(sport: :running, sub_sport: :commuting)).to be(false)
      expect(described_class.commute?(sport: nil)).to be(false)
    end
  end

  describe "bare sports" do
    {
      running: "running",
      cycling: "cycling",
      e_biking: "cycling_electric",
      swimming: "pool_swimming",
      walking: "walking",
      hiking: "hiking",
      training: "fitness",
      fitness_equipment: "fitness",
      cross_country_skiing: "skiing_cross_country",
      alpine_skiing: "skiing_alpine",
      snowboarding: "snowboarding",
      rowing: "rowing",
      mountaineering: "mountaineering",
      snowshoeing: "snowshoes",
      inline_skating: "inline_skating",
      ice_skating: "ice_skating",
      stand_up_paddleboarding: "standup_paddleboarding",
      kayaking: "kayaking",
      windsurfing: "windsurfing",
      tennis: "tennis_outdoor"
    }.each do |sport, slug|
      it "maps #{sport} to #{slug}" do
        expect(slug_for(sport:)).to eq(slug)
      end
    end

    it "falls back to the bare sport for an unlisted sub sport" do
      expect(slug_for(sport: :cycling, sub_sport: :cyclocross)).to eq("cycling")
    end
  end

  describe "activities outside the Allure catalog" do
    # Emitting nothing is deliberate: the import falls back to the selected
    # sport instead of being silently misclassified as something adjacent.
    %i[
      generic transition multisport paddling flying sailing diving snorkeling
      basketball soccer golf motorcycling
    ].each do |sport|
      it "emits no alias for #{sport}" do
        expect(described_class.alias_for(sport:)).to be_nil
      end
    end

    it "emits no alias when the session carries no sport" do
      expect(described_class.alias_for(sport: nil)).to be_nil
    end
  end
end
