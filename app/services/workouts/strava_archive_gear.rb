# frozen_string_literal: true

module Workouts
  # The equipment an archive's activity names (PLAN_STRAVA_ARCHIVE.md §5). The
  # gear is matched against the account's equipment by label, ignoring case;
  # what is missing is created once, typed from `bikes.csv` and `shoes.csv`,
  # else from the sport, with the brand and model as its description. Nothing
  # links it to the archive afterwards: it is the account's own equipment.
  class StravaArchiveGear
    LABEL_LENGTH = 50
    TYPE_BY_SPORT_GROUP = { "ride" => "bike", "run" => "shoes", "hike" => "shoes" }.freeze

    Match = Data.define(:id, :created_label)

    def initialize(user:, items:)
      @user = user
      @items = items
      @matches = {}
    end

    # The equipment for `name`, created when missing, or nil without a name.
    def match(name, sport: nil)
      label = name.to_s.strip.truncate(LABEL_LENGTH, omission: "")
      return nil if label.empty?

      key = label.downcase
      return @matches[key] if @matches.key?(key)

      existing = @user.equipments.find_by("lower(label) = ?", key)
      @matches[key] = existing ? Match.new(id: existing.id, created_label: nil) : create(label, sport)
    end

    private

    def create(label, sport)
      item = @items[Allure::StravaArchive::Gear.key(label)]
      equipment = @user.equipments.create!(
        label:,
        equipment_type: equipment_type(item, sport),
        description: item&.description,
        is_active: true
      )
      Match.new(id: equipment.id, created_label: equipment.label)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      existing = @user.equipments.find_by("lower(label) = ?", label.downcase)
      existing && Match.new(id: existing.id, created_label: nil)
    end

    def equipment_type(item, sport)
      slug = item ? item.kind.to_s : TYPE_BY_SPORT_GROUP[sport&.colour_group]
      (slug && EquipmentType.find_by(slug:)) || EquipmentType.find_by!(slug: "misc")
    end
  end
end
