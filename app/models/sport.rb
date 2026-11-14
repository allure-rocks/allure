# frozen_string_literal: true

class Sport < ApplicationRecord
  # Icon families (DESIGN.md §6). The persisted column keeps its historic
  # `colour_group` name; it is the icon fallback family, not a colour.
  GROUPS = Allure::SportPalette::GROUPS.freeze
  PACE_SPEED_DISPLAYS = %w[pace speed pace_and_speed].freeze
  CADENCE_UNITS = %w[rpm spm].freeze

  # Generic sports an import detects when the file carries no usable sub-type
  # (PLAN_M1.md §3.4). They are the keys of the per-account sport defaults.
  GENERIC_SLUGS = %w[cycling running walking].freeze

  # Choices offered as a per-account default for each generic sport
  # (PLAN_M1.md §3.4.2). A curated list, not the icon family: tennis and padel
  # share the running family, and halfbike and inline skating the cycling one.
  # The generic itself comes first and means "keep the detected generic".
  DEFAULT_TARGET_SLUGS = {
    "cycling" => %w[
      cycling cycling_road cycling_gravel cycling_electric cycling_trekking
      cycling_virtual mountain_biking mountain_biking_electric
    ],
    "running" => %w[running running_virtual trail],
    "walking" => %w[walking hiking]
  }.freeze

  attr_readonly :slug

  has_many :workouts, dependent: :restrict_with_exception
  has_many :segments, dependent: :restrict_with_exception
  has_many :segment_efforts, dependent: :restrict_with_exception
  has_many :records, dependent: :restrict_with_exception
  has_many :best_efforts, dependent: :restrict_with_exception
  has_many :effort_records, dependent: :restrict_with_exception

  scope :catalog_order, -> { order(:position) }
  scope :active, -> { where(active: true) }

  # Sports ordered by their localized display name, accent- and
  # case-insensitive, for every sport dropdown. The default collection is every
  # active sport; catalog order (seed positions) stays the reference order for
  # the styleguide wall and the hub switches.
  def self.alphabetical(sports = active)
    sports.sort_by { |sport| I18n.transliterate(I18n.t("sports.#{sport.slug}", default: sport.label)).downcase }
  end

  # The whole catalog loaded once, for surfaces that resolve a sport per item
  # (the feed resolves one snapshot slug or one remote label per card). Built
  # per call: the catalog is seed data that a request may cache, never the
  # class, so seeds and specs that add a sport stay visible.
  Catalog = Data.define(:by_slug, :by_label) do
    def fetch_slug!(slug)
      by_slug.fetch(slug.to_s) { raise ActiveRecord::RecordNotFound, "Sport #{slug.inspect} is not in the catalog" }
    end

    def find_label(label)
      key = label.to_s.strip.downcase
      key.empty? ? nil : by_label[key]
    end
  end

  def self.catalog
    sports = all.to_a
    Catalog.new(by_slug: sports.index_by(&:slug), by_label: sports.index_by { |sport| sport.label.downcase })
  end

  validates :slug, :label, presence: true, uniqueness: true
  validates :slug, format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :colour_group, inclusion: { in: GROUPS }
  validates :pace_speed_display, inclusion: { in: PACE_SPEED_DISPLAYS }
  validates :pace_basis_metres, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :cadence_unit, inclusion: { in: CADENCE_UNITS }, allow_nil: true
  validates :stopped_speed_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: true
  validates :active, :records_elevation, :records_power, :virtual, inclusion: { in: [ true, false ] }

  def translated_name = I18n.t("sports.#{slug}", raise: true)

  def icon = Allure::SportPalette.icon_for(slug, colour_group)

  # A sport whose pace reads over a fixed reference distance (rowing's /500 m)
  # rather than the viewer's kilometre or mile; its presentation never shows
  # speed.
  def pace_basis? = pace_basis_metres.present?

  # A virtual sport measures the athlete's effort in watts while its speed is a
  # game output: the draft, the gradient, the bike, the rider's weight and the
  # course all feed it (PLAN_VIRTUAL.md §8). A recording that carries power
  # therefore leads with it. Cycling (virtual) is the only catalog sport today;
  # a virtual run keeps its pace and a virtual row its fixed 500 m basis.
  def power_led? = virtual? && pace_speed_display == "speed"

  def grade_adjusted_pace? = records_elevation? && pace_speed_display != "speed"

  # The fastest plausible speed for the sport, used only to flag anomalies
  # (PLAN_M1.md §8.10). A virtual platform draws its own positions, so none
  # applies.
  def speed_ceiling_km_h = virtual? ? nil : Allure::Gpx::Anomalies.speed_ceiling_for(slug)
end
