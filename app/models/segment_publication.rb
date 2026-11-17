# frozen_string_literal: true

# An immutable, sanitized course representation distributed to remote Allure
# instances (docs/dev/SEGMENTS-FEDERATION.md). It carries geometry, name,
# description, sport, and course metrics only: no effort, athlete, alias,
# leaderboard row, or activity timestamp is ever part of it.
class SegmentPublication < ApplicationRecord
  include HasShortId

  STATUSES = %w[active deleted].freeze
  AUDIENCES = %w[public followers].freeze
  REPRESENTATION_KEYS = %w[
    name description sport_slug kind distance ascent descent average_grade
    match_tolerance track location redacted
  ].freeze
  IMMUTABLE_ATTRIBUTES = %i[
    uuid actor_id segment_id object_uri audience source_fingerprint
    representation route_metadata published_at
    sanitized_gpx_blob_id sanitized_route_image_blob_id sanitized_route_image_dark_blob_id
  ].freeze

  belongs_to :actor, inverse_of: :segment_publications
  belongs_to :segment, inverse_of: :segment_publications, optional: true
  has_many :outbox_events,
           class_name: "FederationOutboxEvent",
           foreign_key: :segment_publication_id,
           inverse_of: :segment_publication,
           dependent: :restrict_with_exception

  has_one_attached :gpx, dependent: :purge_later
  has_one_attached :route_image, dependent: :purge_later
  has_one_attached :route_image_dark, dependent: :purge_later

  attr_readonly(*IMMUTABLE_ATTRIBUTES)

  scope :active, -> { where(status: "active") }
  scope :deleted, -> { where(status: "deleted") }

  before_validation :assign_publication_identity, on: :create

  validates :uuid, format: { with: Allure::ShortId::UUID_PATTERN }, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :audience, inclusion: { in: AUDIENCES }
  validates :object_uri, presence: true
  validates :published_at, presence: true
  validates :actor, presence: true
  validates :source_fingerprint, format: { with: /\A\h{64}\z/ }
  validates :segment_id, uniqueness: { conditions: -> { where(status: "active") } }, if: :active?
  validates :deleted_at, presence: true, if: :deleted?
  validates :deleted_at, absence: true, if: :active?
  validate :representation_is_an_object
  validate :route_metadata_is_an_object
  validate :sanitized_blob_content_types
  validate :actor_is_retained_local_actor
  validate :segment_presence_matches_status
  validate :object_uri_matches_identity, on: :create
  validate :status_transition_is_terminal, on: :update

  def self.object_uri_for(uuid)
    Allure::Federation.config.segment_publication_uri(Allure::ShortId.encode(uuid))
  end

  def active? = status == "active"
  def deleted? = status == "deleted"
  def audience_public? = audience == "public"
  def track = representation["track"]
  def publication_name = representation["name"]
  def publication_description = representation["description"]
  def publication_sport_slug = representation["sport_slug"]
  def publication_kind = representation["kind"]

  def sanitized_attachment(name)
    raise ArgumentError, "unknown publication attachment" unless %i[gpx route_image route_image_dark].include?(name.to_sym)

    expected_blob_id = public_send("sanitized_#{name}_blob_id")
    attachment = public_send(name)
    return unless expected_blob_id.present? && attachment.attached?
    return unless attachment.blob.id == expected_blob_id

    attachment
  end

  # The sanitized course image variant matching the requested theme, with the
  # other variant as fallback (DESIGN.md §15.4).
  def route_image_variant(theme)
    requested, fallback = if theme.to_s == "dark"
      [ sanitized_attachment(:route_image_dark), sanitized_attachment(:route_image) ]
    else
      [ sanitized_attachment(:route_image), sanitized_attachment(:route_image_dark) ]
    end
    requested || fallback
  end

  def mark_deleted!
    return self if deleted?

    update!(status: "deleted", deleted_at: Time.current)
    segment&.association(:active_publication)&.reset
    self
  end

  # The route image renders asynchronously on the route_images worker. The
  # reference is written once, from nil, and the relation write is the
  # controlled exception to immutability, like WorkoutPublication. Both
  # variants are written the same way.
  def attach_sanitized_route_image!(blob)
    attach_sanitized_route_image_variant!(:route_image, blob)
  end

  def attach_sanitized_route_image_dark!(blob)
    attach_sanitized_route_image_variant!(:route_image_dark, blob)
  end

  def route_image_pending?
    sanitized_route_image_blob_id.blank?
  end

  def publication_document
    Federation::Serializers::SegmentNote.new(publication: self, actor:).call
  end

  private

  def attach_sanitized_route_image_variant!(name, blob)
    column = :"sanitized_#{name}_blob_id"
    with_lock do
      return self if public_send(column).present?

      public_send(name).attach(blob)
      self.class.where(id: id).update_all(column => blob.id, updated_at: Time.current)
      reload
    end
    self
  end

  def assign_publication_identity
    self.uuid ||= SecureRandom.uuid
    self.object_uri ||= self.class.object_uri_for(uuid) if uuid.to_s.match?(Allure::ShortId::UUID_PATTERN)
    self.published_at ||= Time.current
  end

  def representation_is_an_object
    unless representation.is_a?(Hash)
      errors.add(:representation, :invalid)
      return
    end

    errors.add(:representation, :invalid) unless representation.keys.map(&:to_s).all? { REPRESENTATION_KEYS.include?(_1) }
    if representation["redacted"] == true
      errors.add(:representation, :invalid) if representation.keys.map(&:to_s).any? { %w[track location].include?(_1) }
    elsif !representation["redacted"].nil?
      errors.add(:representation, :invalid)
    end
    validate_name
    validate_description
    validate_sport
    validate_kind
    validate_course_metrics
    validate_track(representation["track"]) if representation.key?("track")
    validate_location(representation["location"]) if representation.key?("location")
  end

  def validate_name
    name = representation["name"]
    errors.add(:representation, :invalid) unless name.is_a?(String) && name.length.between?(1, 120)
  end

  def validate_description
    description = representation["description"]
    return if description.nil?

    errors.add(:representation, :invalid) unless description.is_a?(String) && description.length <= 2_000
  end

  def validate_sport
    slug = representation["sport_slug"]
    return if slug.nil?

    errors.add(:representation, :invalid) unless slug.is_a?(String) && slug.present?
  end

  def validate_kind
    errors.add(:representation, :invalid) unless representation["kind"] == "segment"
  end

  def validate_course_metrics
    distance = representation["distance"]
    errors.add(:representation, :invalid) unless distance.is_a?(Numeric) && distance.to_f.positive? && distance.to_f.finite?

    %w[ascent descent].each do |key|
      value = representation[key]
      next if value.nil?

      errors.add(:representation, :invalid) unless value.is_a?(Numeric) && value.to_f.finite? && value.to_f >= 0
    end

    grade = representation["average_grade"]
    if !grade.nil? && !(grade.is_a?(Numeric) && grade.to_f.finite?)
      errors.add(:representation, :invalid)
    end

    tolerance = representation["match_tolerance"]
    unless tolerance.is_a?(Integer) && tolerance.between?(5, 100)
      errors.add(:representation, :invalid)
    end
  end

  # The course is exactly one recording-independent LineString. The
  # `segment_index: 0` property keeps the shape identical to a workout track,
  # so one map controller reads both.
  def validate_track(track)
    unless track.is_a?(Hash) && track.keys.map(&:to_s).sort == %w[features type] && track["type"] == "FeatureCollection"
      errors.add(:representation, :invalid)
      return
    end

    features = track["features"]
    unless features.is_a?(Array) && features.length == 1
      errors.add(:representation, :invalid)
      return
    end

    feature = features.first
    valid = feature.is_a?(Hash) &&
      feature.keys.map(&:to_s).sort == %w[geometry properties type] &&
      feature["type"] == "Feature" &&
      feature["properties"].is_a?(Hash) &&
      feature["properties"].keys.map(&:to_s) == [ "segment_index" ] &&
      feature["properties"]["segment_index"] == 0 &&
      valid_line_string?(feature["geometry"])
    errors.add(:representation, :invalid) unless valid
  end

  def valid_line_string?(geometry)
    geometry.is_a?(Hash) &&
      geometry.keys.map(&:to_s).sort == %w[coordinates type] &&
      geometry["type"] == "LineString" &&
      geometry["coordinates"].is_a?(Array) &&
      geometry["coordinates"].length >= 2 &&
      geometry["coordinates"].all? { |point| valid_coordinate?(point) }
  end

  def valid_coordinate?(point)
    point.is_a?(Array) && point.length == 2 &&
      point[0].is_a?(Numeric) && point[1].is_a?(Numeric) &&
      point[0].to_f.finite? && point[1].to_f.finite? &&
      point[0].between?(-180, 180) && point[1].between?(-90, 90)
  end

  def validate_location(location)
    valid = location.is_a?(Hash) &&
      location.keys.map(&:to_s).sort == %w[latitude longitude] &&
      valid_coordinate?([ location["longitude"], location["latitude"] ])
    errors.add(:representation, :invalid) unless valid
  end

  def route_metadata_is_an_object
    unless route_metadata.is_a?(Hash)
      errors.add(:route_metadata, :invalid)
      return
    end

    errors.add(:route_metadata, :invalid) unless route_metadata.keys.map(&:to_s).all? { %w[bounds segments_count].include?(_1) }
    bounds = route_metadata["bounds"]
    errors.add(:route_metadata, :invalid) unless bounds.is_a?(Array) && bounds.length == 4 &&
      bounds.all? { |value| value.is_a?(Numeric) && value.to_f.finite? }
    segments_count = route_metadata["segments_count"]
    errors.add(:route_metadata, :invalid) unless segments_count.is_a?(Integer) && segments_count.positive?
  end

  def sanitized_blob_content_types
    {
      sanitized_gpx_blob_id: "application/gpx+xml",
      sanitized_route_image_blob_id: "image/png",
      sanitized_route_image_dark_blob_id: "image/png"
    }.each do |attribute, content_type|
      blob_id = public_send(attribute)
      next if blob_id.blank?

      blob = ActiveStorage::Blob.find_by(id: blob_id)
      errors.add(attribute, :invalid) unless blob&.content_type == content_type
    end
  end

  def actor_is_retained_local_actor
    return if actor.blank?

    unless actor.local? && !actor.tombstoned?
      errors.add(:actor, :invalid)
      return
    end

    return if segment.blank?
    return if actor.user_id == segment.user_id

    errors.add(:actor, :invalid)
  end

  def segment_presence_matches_status
    if active? && segment_id.blank?
      errors.add(:segment, :blank)
    elsif deleted? && segment_id.present? && segment.blank?
      errors.add(:segment, :invalid)
    end
  end

  def object_uri_matches_identity
    return unless uuid.to_s.match?(Allure::ShortId::UUID_PATTERN)

    errors.add(:object_uri, :invalid) unless object_uri == self.class.object_uri_for(uuid)
  end

  def status_transition_is_terminal
    return unless will_save_change_to_status?

    errors.add(:status, :invalid) unless status_in_database == "active" && deleted?
  end
end
