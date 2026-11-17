# frozen_string_literal: true

require "uri"

# A safe received representation of a remote Allure course. It is never a
# local segment: no effort, athlete, alias, or leaderboard data, and no
# editing surface (docs/dev/SEGMENTS-FEDERATION.md). Content is immutable
# except for the controlled deletion and location-redaction paths.
class RemoteSegment < ApplicationRecord
  STATUSES = %w[active deleted].freeze
  AUDIENCES = %w[public followers].freeze
  REPRESENTATION_KEYS = %w[
    name description sport_slug kind distance ascent descent average_grade
    match_tolerance track location redacted
  ].freeze
  AUDIT_KEYS = %w[
    name description sport_slug kind distance ascent descent average_grade
    match_tolerance
  ].freeze

  IMMUTABLE_ATTRIBUTES = %i[
    actor_id object_uri activity_uri source_domain name description content_html
    sport_label kind distance ascent descent average_grade published_at
    received_at representation route_metadata raw warnings
  ].freeze

  belongs_to :actor, inverse_of: :remote_segments
  has_many :recipients, class_name: "RemoteSegmentRecipient", dependent: :destroy, inverse_of: :remote_segment
  has_many :attachments, class_name: "RemoteSegmentAttachment", dependent: :destroy, inverse_of: :remote_segment
  has_many :local_copies, class_name: "Segment", dependent: :nullify, inverse_of: :remote_segment

  attr_readonly(*IMMUTABLE_ATTRIBUTES)

  scope :active, -> { where(status: "active") }
  scope :deleted, -> { where(status: "deleted") }
  scope :entitled_to, ->(actor) {
    active.joins(:recipients).merge(RemoteSegmentRecipient.active.where(recipient_actor: actor))
  }

  validates :object_uri, presence: true, uniqueness: true
  validates :activity_uri, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :audience, inclusion: { in: AUDIENCES }
  validates :source_domain, presence: true, length: { maximum: 255 }
  validates :received_at, presence: true
  validates :published_at, presence: true
  validates :kind, inclusion: { in: %w[segment] }
  validates :name, presence: true, length: { maximum: 120 }, if: :active?
  validates :description, length: { maximum: 2_000 }, allow_nil: true
  validates :distance, numericality: { greater_than: 0 }, allow_nil: true
  validates :ascent, :descent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_grade,
            numericality: { greater_than_or_equal_to: -100, less_than_or_equal_to: 100 },
            allow_nil: true
  validate :uris_are_absolute
  validate :source_domain_matches_actor
  validate :status_matches_deleted_at
  validate :json_columns_are_objects
  validate :warnings_is_an_array
  validate :representation_is_valid

  def active? = status == "active"
  def deleted? = status == "deleted"
  def public? = audience == "public"
  def location_data_purged? = location_data_purged_at.present?

  def entitled_to?(actor)
    return false unless actor

    recipients.active.exists?(recipient_actor: actor)
  end

  def mark_deleted!(at: Time.current)
    with_lock do
      return self if deleted?

      update!(status: "deleted", deleted_at: at)
    end
  end

  # Controlled write of the parsed remote course geometry, performed by the
  # media pipeline under a lock. The course has no chart, so the `chart:`
  # argument carried by the shared processor is ignored. A fetch that finishes
  # after deletion is a no-op.
  def attach_remote_media!(track:, route_metadata:, at: Time.current, chart: nil)
    return self if deleted?

    with_lock do
      return self if deleted?

      merged = representation.except("track").merge("track" => track)
      self.class.where(id: id).update_all(
        representation: merged,
        route_metadata:,
        updated_at: at
      )
    end
    reload
  end

  # Controlled redaction of location-bearing data, called by Delete processing
  # and by the media purge. Ordinary updates cannot touch a snapshot, so this
  # writes through the relation deliberately.
  def redact_location!(at: Time.current)
    return self if location_data_purged?

    with_lock do
      audit = representation.slice(*AUDIT_KEYS)
      self.class.where(id: id).update_all(
        representation: audit.merge("redacted" => true),
        route_metadata: { "redacted" => true },
        location_data_purged_at: at,
        updated_at: Time.current
      )
    end
    reload
  end

  private

  def uris_are_absolute
    %i[object_uri activity_uri].each do |attribute|
      value = public_send(attribute)
      next if value.blank?
      next if absolute_uri?(value)

      errors.add(attribute, :invalid)
    end
  end

  def absolute_uri?(value)
    parsed = URI.parse(value.to_s)
    parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
      parsed.userinfo.blank? && parsed.query.blank? && parsed.fragment.blank?
  rescue URI::InvalidURIError, URI::InvalidComponentError
    false
  end

  def source_domain_matches_actor
    return if actor.blank? || source_domain.blank?

    errors.add(:source_domain, :invalid) unless Allure::Federation::Authority.domain(actor.uri) == source_domain
  end

  def status_matches_deleted_at
    errors.add(:deleted_at, :invalid) unless deleted? == deleted_at.present?
  end

  def json_columns_are_objects
    %i[representation route_metadata raw].each do |attribute|
      errors.add(attribute, :invalid) unless public_send(attribute).is_a?(Hash)
    end
  end

  def warnings_is_an_array
    errors.add(:warnings, :invalid) unless warnings.is_a?(Array)
  end

  def representation_is_valid
    unless representation.is_a?(Hash)
      errors.add(:representation, :invalid)
      return
    end

    errors.add(:representation, :invalid) unless representation.keys.map(&:to_s).all? { |key| REPRESENTATION_KEYS.include?(key) }
    errors.add(:representation, :invalid) unless representation["sport_slug"].nil? || representation["sport_slug"].is_a?(String)
    if representation["redacted"] == true
      errors.add(:representation, :invalid) if representation.keys.map(&:to_s).any? { |key| %w[track location].include?(key) }
    elsif !representation["redacted"].nil?
      errors.add(:representation, :invalid)
    end

    validate_active_representation if active?
    validate_course_metrics
    validate_track(representation["track"]) if representation.key?("track")
    validate_location(representation["location"]) if representation.key?("location")
  end

  def validate_active_representation
    name = representation["name"]
    errors.add(:representation, :invalid) unless name.is_a?(String) && name.length.between?(1, 120)
    errors.add(:representation, :invalid) unless representation["kind"] == "segment"
  end

  def validate_course_metrics
    distance = representation["distance"]
    errors.add(:representation, :invalid) if distance && !(distance.is_a?(Numeric) && distance.to_f.positive?)
    %w[ascent descent].each do |key|
      value = representation[key]
      errors.add(:representation, :invalid) if value && !(value.is_a?(Numeric) && value.to_f >= 0)
    end
    grade = representation["average_grade"]
    errors.add(:representation, :invalid) if grade && !(grade.is_a?(Numeric) && grade.to_f.between?(-100, 100))
    tolerance = representation["match_tolerance"]
    errors.add(:representation, :invalid) if tolerance && !(tolerance.is_a?(Integer) && tolerance.between?(5, 100))
  end

  # A course is exactly one LineString; the `segment_index: 0` property keeps
  # the shape identical to a workout track, so one map controller reads both.
  def validate_track(track)
    unless track.is_a?(Hash) && track.keys.map(&:to_s).sort == %w[features type] &&
        track["type"] == "FeatureCollection" && track["features"].is_a?(Array) && track["features"].length == 1
      errors.add(:representation, :invalid)
      return
    end

    feature = track["features"].first
    valid = feature.is_a?(Hash) && feature.keys.map(&:to_s).sort == %w[geometry properties type] &&
      feature["type"] == "Feature" && feature["properties"].is_a?(Hash) &&
      feature["properties"].keys.map(&:to_s) == [ "segment_index" ] &&
      feature["properties"]["segment_index"] == 0 &&
      valid_line_string?(feature["geometry"])
    errors.add(:representation, :invalid) unless valid
  end

  def valid_line_string?(geometry)
    geometry.is_a?(Hash) && geometry.keys.map(&:to_s).sort == %w[coordinates type] && geometry["type"] == "LineString" &&
      geometry["coordinates"].is_a?(Array) && geometry["coordinates"].length >= 2 &&
      geometry["coordinates"].all? { |point| valid_coordinate?(point) }
  end

  def valid_coordinate?(point)
    point.is_a?(Array) && point.length == 2 &&
      point[0].is_a?(Numeric) && point[1].is_a?(Numeric) &&
      point[0].to_f.finite? && point[1].to_f.finite? &&
      point[0].between?(-180, 180) && point[1].between?(-90, 90)
  end

  def validate_location(location)
    valid = location.is_a?(Hash) && location.keys.map(&:to_s).sort == %w[latitude longitude] &&
      valid_coordinate?([ location["longitude"], location["latitude"] ])
    errors.add(:representation, :invalid) unless valid
  end
end
