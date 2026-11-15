# frozen_string_literal: true

class PublishingProfile < ApplicationRecord
  AUDIENCES = %w[public followers].freeze
  BUILT_IN_KEYS = AUDIENCES
  SETTING_KEYS = %w[
    title description metrics route route_image basemap gpx records device commute weather comments mask_start
    mask_finish photos photo_captions photo_positions
  ].freeze
  BOOLEAN_SETTING_KEYS = %w[
    title description route route_image basemap gpx records device commute weather comments mask_start mask_finish
    photos photo_captions photo_positions
  ].freeze
  # Settings a frozen publication snapshot may still carry after the setting
  # was retired. `segment` gated segment leaderboards until the board followed
  # the reader and the shared route (PLAN_SEGMENTS.md §8.2); it is ignored.
  LEGACY_SNAPSHOT_SETTING_KEYS = %w[segment].freeze
  METRIC_KEYS = %w[
    distance duration moving_time pause_time ascent descent min_elevation max_elevation
    average_speed max_speed average_pace best_pace grade_adjusted_pace
    average_heart_rate max_heart_rate
    average_cadence max_cadence average_power max_power calories
  ].freeze
  # Heart rate is health data (PLAN_HEART_RATE.md D7): a new profile shares
  # none until its owner ticks it. Existing profiles keep their stored list.
  HEALTH_METRIC_KEYS = %w[average_heart_rate max_heart_rate].freeze
  # The form's three groups, in METRIC_KEYS order.
  METRIC_GROUPS = {
    "course" => %w[distance duration moving_time pause_time ascent descent min_elevation max_elevation],
    "speed" => %w[average_speed max_speed average_pace best_pace grade_adjusted_pace],
    "sensors" => %w[average_heart_rate max_heart_rate average_cadence max_cadence average_power max_power calories]
  }.freeze
  # The safety delay before a publication becomes visible or federated
  # (docs/dev/DELAYED-PUBLISHING.md). A profile policy, not a snapshot setting: the
  # published representation is unchanged. `immediate` (0) is the default:
  # publishing is direct unless the owner opts into a hold. The owner may pick
  # another preset for one publish; the profile value is the default.
  PUBLISH_DELAYS = {
    "immediate" => 0,
    "1_day" => 86_400,
    "3_days" => 259_200,
    "1_week" => 604_800,
    "2_weeks" => 1_209_600,
    "1_month" => 2_592_000
  }.freeze
  PUBLISH_DELAY_VALUES = PUBLISH_DELAYS.values.freeze
  DEFAULT_SETTINGS = {
    "title" => true,
    "description" => true,
    "metrics" => METRIC_KEYS - HEALTH_METRIC_KEYS,
    "route" => true,
    "gpx" => false,
    "records" => false,
    "device" => false,
    "commute" => false,
    "weather" => false,
    "comments" => true,
    "route_image" => true,
    "basemap" => true,
    "mask_start" => true,
    "mask_finish" => true,
    # Photos are shared only by an explicit choice (PLAN_PHOTOS.md §5.1).
    "photos" => false,
    "photo_captions" => false,
    "photo_positions" => false
  }.freeze
  # Settings added after profiles already existed, whose absence keeps the
  # behaviour those profiles had: comments were open before the setting.
  ABSENT_MEANS_ENABLED_KEYS = %w[comments].freeze

  belongs_to :user, inverse_of: :publishing_profiles
  has_many :workout_publications, inverse_of: :publishing_profile, dependent: :nullify
  has_many :workout_auto_publications, inverse_of: :publishing_profile, dependent: :nullify

  # Automatic publishing (docs/dev/AUTO-PUBLISHING.md) is a profile policy like the
  # delay, never a snapshot setting. Off by default; turning it on requires the
  # owner to acknowledge what it does, once, in the same submission.
  attribute :auto_publish_acknowledged, :boolean, default: false

  scope :automatic, -> { where(auto_publish: true) }

  before_validation :apply_default_settings, on: :create

  validates :name, presence: true, length: { in: 1..120 }
  validates :audience, inclusion: { in: AUDIENCES }
  validates :built_in_key, inclusion: { in: BUILT_IN_KEYS }, allow_nil: true
  validates :built_in_key, uniqueness: { scope: :user_id }, allow_nil: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :publish_delay_seconds,
            numericality: { only_integer: true },
            inclusion: { in: PUBLISH_DELAY_VALUES }
  validates :settings, presence: true
  validate :settings_are_allowlisted
  validate :built_in_audience_is_fixed
  validate :custom_audience_is_public
  validates :auto_publish, :auto_publish_exclude_commute, inclusion: { in: [ true, false ] }
  validate :auto_publish_is_allowed, if: -> { auto_publish? && will_save_change_to_auto_publish? }
  validate :auto_publish_audience_is_free, if: :auto_publish?
  validate :auto_publish_excluded_sports_are_known, if: :will_save_change_to_auto_publish_excluded_sports?

  def self.setting_enabled?(settings, key)
    value = settings.to_h.stringify_keys[key.to_s]
    ABSENT_MEANS_ENABLED_KEYS.include?(key.to_s) ? value != false : value == true
  end

  def built_in? = built_in_key.present?

  # Only the built-in followers profile can ever carry the followers audience;
  # custom profiles stay public-only through `custom_audience_is_public`. The
  # followers audience is always available: its local followers read it
  # whatever the switches say, and FEDERATION_RESTRICTED_ENABLED only decides
  # whether it also reaches approved instances (docs/dev/FEDERATION.md).
  def publishable?
    audience == "public" || built_in_key == "followers"
  end

  def self.ensure_built_ins_for!(user)
    transaction do
      AUDIENCES.each_with_index do |audience, position|
        find_or_create_by!(user:, built_in_key: audience) do |profile|
          profile.name = I18n.t("publishing_profiles.defaults.#{audience}.name")
          profile.audience = audience
          profile.settings = DEFAULT_SETTINGS.deep_dup
          profile.position = position
        end
      end
    end
  end

  def settings=(value)
    super(value.is_a?(Hash) ? value.stringify_keys : value)
  end

  # Automatic publishing's sport exclusion (docs/dev/AUTO-PUBLISHING.md), a
  # profile policy like the commute exclusion: the workouts of these sports are
  # never published by themselves. Sorted and unique, so saving the same choice
  # is not a change.
  def auto_publish_excluded_sports=(value)
    super(Array(value).compact_blank.map(&:to_s).uniq.sort)
  end

  def auto_publish_excludes_sport?(sport) = auto_publish_excluded_sports.include?(sport.slug)

  private

  # A slug the catalog does not know would never match a workout. Only checked
  # when the list changes, so an unrelated save is never blocked.
  def auto_publish_excluded_sports_are_known
    slugs = auto_publish_excluded_sports
    return if slugs.empty? || Sport.where(slug: slugs).count == slugs.size

    errors.add(:base, :auto_publish_excluded_sports_unknown)
  end

  def apply_default_settings
    self.settings = DEFAULT_SETTINGS.deep_dup if settings.blank?
  end

  def settings_are_allowlisted
    unless settings.is_a?(Hash)
      errors.add(:settings, :invalid)
      return
    end

    keys = settings.keys.map(&:to_s)
    errors.add(:settings, :invalid) if (keys - SETTING_KEYS).any?

    BOOLEAN_SETTING_KEYS.each do |key|
      value = settings[key]
      errors.add(:settings, :invalid) unless value.nil? || value == true || value == false
    end

    metrics = settings["metrics"]
    return if metrics.nil?

    errors.add(:settings, :invalid) unless metrics.is_a?(Array) && metrics.all? { |metric| METRIC_KEYS.include?(metric.to_s) }
  end

  def built_in_audience_is_fixed
    return if built_in_key.blank? || audience == built_in_key

    errors.add(:audience, :invalid)
  end

  def custom_audience_is_public
    return if built_in_key.present? || audience == "public"

    errors.add(:audience, :followers_unavailable)
  end

  def auto_publish_is_allowed
    errors.add(:base, :auto_publish_unavailable) unless publishable?
    errors.add(:base, :auto_publish_unacknowledged) unless auto_publish_acknowledged
  end

  # One automatic profile per audience, mirroring the partial unique index: an
  # import publishes at most one publication per audience.
  def auto_publish_audience_is_free
    others = PublishingProfile.automatic.where(user_id:, audience:)
    others = others.where.not(id:) if persisted?
    errors.add(:base, :auto_publish_taken) if others.exists?
  end
end
