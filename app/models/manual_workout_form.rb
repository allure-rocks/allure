# frozen_string_literal: true

# The web form of a manual entry (PLAN_MANUAL_ENTRY.md §5): what the owner
# types, in their own units and time zone, kept as typed so a refused form
# comes back unchanged. `to_attributes` turns it into the SI figures
# Workouts::ManualEntry persists; the model's own refusals come back onto the
# fields through `adopt_errors`.
class ManualWorkoutForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  TIME_FORMAT = "%Y-%m-%dT%H:%M"
  LOCAL_TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?\z/
  DECIMAL = /\A\d+(\.\d+)?\z/
  INTEGER = /\A\d+\z/
  INTEGER_FIELDS = %i[average_heart_rate max_heart_rate calories average_power].freeze
  DURATION_PARTS = %i[hours minutes seconds].freeze

  # The field each refusal of the model is shown under.
  ERROR_FIELDS = {
    sport: :sport_id, started_at: :started_at, duration: :duration, moving_time: :moving_time,
    pause_time: :moving_time, distance: :distance, ascent: :ascent,
    average_heart_rate: :average_heart_rate, max_heart_rate: :max_heart_rate,
    calories: :calories, average_power: :average_power,
    title: :title, description: :description, notes: :notes
  }.freeze

  attribute :sport_id, :string
  attribute :started_at, :string
  DURATION_PARTS.each do |part|
    attribute :"duration_#{part}", :string
    attribute :"moving_#{part}", :string
  end
  attribute :distance, :string
  attribute :ascent, :string
  INTEGER_FIELDS.each { |field| attribute field, :string }
  attribute :title, :string
  attribute :description, :string
  attribute :notes, :string
  attribute :commute, :boolean, default: false
  attribute :equipment_ids, default: -> { [] }

  attr_accessor :unit_system, :time_zone

  def self.model_name = ActiveModel::Name.new(self, nil, "ManualWorkout")

  def self.human_attribute_name(attribute, options = {})
    I18n.t("workouts.manual.fields.#{attribute}", default: super)
  end

  def self.blank(user:)
    zone = zone_for(user)
    new(unit_system: user.unit_system, time_zone: zone,
        started_at: Time.current.in_time_zone(zone).strftime(TIME_FORMAT))
  end

  def self.from_workout(workout, user:)
    zone = zone_for(user)
    form = new(unit_system: user.unit_system, time_zone: zone)
    form.assign_attributes(
      sport_id: workout.sport_id.to_s,
      started_at: workout.started_at.in_time_zone(zone).strftime(TIME_FORMAT),
      distance: (form.send(:display_distance, workout.distance) if workout.distance.to_f.positive?),
      ascent: (form.send(:display_ascent, workout.ascent) if workout.ascent.to_f.positive?),
      title: workout.title, description: workout.description, notes: workout.notes,
      commute: workout.commute, equipment_ids: workout.equipment_ids.map(&:to_s),
      **INTEGER_FIELDS.to_h { |field| [ field, workout.public_send(field)&.to_s ] },
      **duration_parts(:duration, workout.duration),
      **(workout.moving_time == workout.duration ? {} : duration_parts(:moving, workout.moving_time))
    )
    form
  end

  def self.from_params(params, user:)
    zone = zone_for(user)
    new(params.to_h.symbolize_keys.slice(*attribute_names.map(&:to_sym))
              .merge(unit_system: user.unit_system, time_zone: zone))
  end

  def self.zone_for(user) = Time.find_zone(user.time_zone.presence) || Time.zone

  def self.duration_parts(prefix, seconds)
    seconds = seconds.to_i
    { "#{prefix}_hours": (seconds / 3600).to_s, "#{prefix}_minutes": (seconds % 3600 / 60).to_s,
      "#{prefix}_seconds": (seconds % 60).to_s }
  end

  def imperial? = unit_system == "imperial"

  # The SI attributes for Workouts::ManualEntry, or nil with the field errors
  # added when something typed cannot be read.
  def to_attributes
    errors.clear
    attributes = {
      sport: parse_sport,
      started_at: parse_started_at,
      duration: parse_duration(:duration, required: true),
      moving_time: parse_duration(:moving),
      distance: parse_decimal(:distance)&.then { imperial? ? it * Allure::Units::METRES_PER_MILE : it * Allure::Units::METRES_PER_KILOMETRE },
      ascent: parse_decimal(:ascent)&.then { imperial? ? it * Allure::Units::METRES_PER_FOOT : it },
      title: title.to_s.strip.presence,
      description: description.to_s.strip.presence,
      notes: notes.to_s.strip.presence,
      commute: commute ? true : false,
      **INTEGER_FIELDS.to_h { |field| [ field, parse_integer(field) ] }
    }
    errors.empty? ? attributes.transform_values { it.is_a?(Float) ? it.round(2) : it } : nil
  end

  def submitted_equipment_ids = Array(equipment_ids).compact_blank.map(&:to_i)

  def adopt_errors(workout)
    workout.errors.each do |error|
      errors.add(ERROR_FIELDS.fetch(error.attribute, :base), error.message)
    end
  end

  private

  def parse_sport
    sport = Sport.active.find_by(id: sport_id) if sport_id.present?
    errors.add(:sport_id, I18n.t("workouts.manual.errors.sport")) unless sport
    sport
  end

  def parse_started_at
    value = started_at.to_s.strip
    time = time_zone.parse(value) if value.match?(LOCAL_TIME)
    errors.add(:started_at, I18n.t("workouts.manual.errors.started_at")) unless time
    time
  rescue ArgumentError
    errors.add(:started_at, I18n.t("workouts.manual.errors.started_at"))
    nil
  end

  def parse_duration(prefix, required: false)
    values = DURATION_PARTS.map { public_send(:"#{prefix}_#{it}").to_s.strip }
    field = prefix == :moving ? :moving_time : :duration
    if values.all?(&:blank?)
      errors.add(field, I18n.t("workouts.manual.errors.duration")) if required
      return nil
    end
    unless values.all? { it.blank? || it.match?(INTEGER) }
      errors.add(field, I18n.t("workouts.manual.errors.duration"))
      return nil
    end

    hours, minutes, seconds = values.map(&:to_i)
    total = (hours * 3600) + (minutes * 60) + seconds
    errors.add(field, I18n.t("workouts.manual.errors.duration")) if total.zero?
    total
  end

  def parse_decimal(field)
    value = normalized_number(public_send(field))
    return nil if value.empty?
    return value.to_f if value.match?(DECIMAL)

    errors.add(field, I18n.t("workouts.manual.errors.number"))
    nil
  end

  def parse_integer(field)
    value = normalized_number(public_send(field))
    return nil if value.empty?
    return value.to_i if value.match?(INTEGER)

    errors.add(field, I18n.t("workouts.manual.errors.whole_number"))
    nil
  end

  def normalized_number(value) = value.to_s.strip.delete(" \u00a0\u202f").tr(",", ".")

  def display_distance(metres)
    value = imperial? ? Allure::Units.metres_to_miles(metres) : Allure::Units.metres_to_kilometres(metres)
    localized(value.round(2))
  end

  def display_ascent(metres)
    (imperial? ? Allure::Units.metres_to_feet(metres) : metres.to_f).round.to_s
  end

  def localized(value)
    text = value.to_d.to_s("F").sub(/\.0\z/, "")
    text.tr(".", I18n.t("number.format.separator"))
  end
end
