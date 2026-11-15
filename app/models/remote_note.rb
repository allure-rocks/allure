# frozen_string_literal: true

require "uri"

# A safe received representation of a remote Allure publication. It is never a
# local workout: no source geometry, no owner attachments, no editing surface
# (docs/dev/FEDERATION.md). Content is immutable except for the controlled deletion and
# location-redaction paths.
class RemoteNote < ApplicationRecord
  STATUSES = %w[active deleted].freeze
  AUDIENCES = %w[public followers].freeze
  REPRESENTATION_KEYS = %w[
    title description sport_label started_at metrics record_types record_distances
    device commute weather comments_closed track chart location redacted
  ].freeze
  AUDIT_KEYS = %w[title description sport_label started_at metrics].freeze

  IMMUTABLE_ATTRIBUTES = %i[
    actor_id object_uri activity_uri source_domain title description content_html
    sport_label started_at published_at received_at metrics representation
    route_metadata raw warnings
  ].freeze

  belongs_to :actor, inverse_of: :remote_notes
  has_many :recipients, class_name: "RemoteNoteRecipient", dependent: :destroy, inverse_of: :remote_note
  has_many :attachments, class_name: "RemoteNoteAttachment", dependent: :destroy, inverse_of: :remote_note
  has_many :reactions, dependent: :destroy, inverse_of: :remote_note
  has_many :comments, dependent: :delete_all, inverse_of: :remote_note

  attr_readonly(*IMMUTABLE_ATTRIBUTES)

  scope :active, -> { where(status: "active") }
  scope :deleted, -> { where(status: "deleted") }
  scope :entitled_to, ->(actor) {
    active.joins(:recipients).merge(RemoteNoteRecipient.active.where(recipient_actor: actor))
  }

  validates :object_uri, presence: true, uniqueness: true
  validates :activity_uri, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :audience, inclusion: { in: AUDIENCES }
  validates :source_domain, presence: true, length: { maximum: 255 }
  validates :received_at, presence: true
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

  # Controlled write of the parsed remote geometry, performed by the media
  # pipeline under a lock. Track and chart arrive together from one GPX parse;
  # a fetch that finishes after deletion is a no-op.
  def attach_remote_media!(track:, chart:, route_metadata:, at: Time.current)
    return self if deleted?

    with_lock do
      return self if deleted?

      merged = representation.except("track", "chart").merge("track" => track, "chart" => chart)
      self.class.where(id: id).update_all(
        representation: merged,
        route_metadata:,
        updated_at: at
      )
    end
    reload
  end

  # Controlled redaction of location-bearing data, called by Delete processing
  # and later by the media purge. Ordinary updates cannot touch a publication-
  # style snapshot, so this writes through the relation deliberately.
  def redact_location!(at: Time.current)
    return self if location_data_purged?

    with_lock do
      audit = representation.slice(*AUDIT_KEYS)
      # `representation` is attr_readonly; the controlled redaction path writes
      # through the relation exactly like the local publication cleanup does.
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
    %i[metrics representation route_metadata raw].each do |attribute|
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
    errors.add(:representation, :invalid) unless representation["sport_label"].nil? || representation["sport_label"].is_a?(String)
    errors.add(:representation, :invalid) unless representation["started_at"].nil? || valid_timestamp?(representation["started_at"])
    if representation["redacted"] == true
      errors.add(:representation, :invalid) if representation.keys.map(&:to_s).any? { |key| %w[track chart location].include?(key) }
    elsif !representation["redacted"].nil?
      errors.add(:representation, :invalid)
    end

    metrics = representation["metrics"]
    if metrics && (!metrics.is_a?(Hash) || metrics.keys.any? { |key| !PublishingProfile::METRIC_KEYS.include?(key.to_s) } || metrics.values.any? { |value| !value.is_a?(Numeric) })
      errors.add(:representation, :invalid)
    end

    validate_record_tokens(representation["record_types"], Record::TYPES)
    validate_record_tokens(representation["record_distances"], Allure::Gpx::BestEfforts::DISTANCES.keys)
    validate_device(representation["device"])
    validate_commute(representation["commute"])
    errors.add(:representation, :invalid) if representation.key?("weather") && !Allure::Weather::Summary.valid?(representation["weather"])
    validate_comments_closed(representation["comments_closed"])
    validate_track(representation["track"]) if representation.key?("track")
    validate_chart(representation["chart"]) if representation.key?("chart")
    validate_location(representation["location"]) if representation.key?("location")
  end

  def validate_record_tokens(value, allowlist)
    return if value.nil?

    valid = value.is_a?(Array) && value.length <= 32 &&
      value.uniq.length == value.length &&
      value.all? { |token| token.is_a?(String) && allowlist.include?(token) }
    errors.add(:representation, :invalid) unless valid
  end

  # The device string is a bounded non-blank display value when present; the
  # parser already truncates it, this is the persistence boundary.
  def validate_device(value)
    return if value.nil?

    max = Federation::Parsers::RemoteNote::MAX_DEVICE
    errors.add(:representation, :invalid) unless value.is_a?(String) && value.present? && value.length <= max
  end

  # The commute flag is a boolean when present; the parser only ever stores
  # true/false and omits it otherwise.
  def validate_commute(value)
    return if value.nil?

    errors.add(:representation, :invalid) unless value == true || value == false
  end

  # A closed thread is presence-only, like the origin's snapshot: the parser
  # stores `true` from the `comments` tag and omits the key otherwise
  # (PLAN_COMMENTS.md §6.4).
  def validate_comments_closed(value)
    return if value.nil?

    errors.add(:representation, :invalid) unless value == true
  end

  def validate_track(track)
    unless track.is_a?(Hash) && track.keys.map(&:to_s).sort == %w[features type] && track["type"] == "FeatureCollection" && track["features"].is_a?(Array) && track["features"].any?
      errors.add(:representation, :invalid)
      return
    end

    valid = track["features"].all? do |feature|
      feature.is_a?(Hash) && feature.keys.map(&:to_s).sort == %w[geometry properties type] &&
        feature["type"] == "Feature" && feature["properties"].is_a?(Hash) &&
        feature["properties"].keys.map(&:to_s) == [ "segment_index" ] &&
        feature["properties"]["segment_index"].is_a?(Integer) &&
        valid_line_string?(feature["geometry"])
    end
    errors.add(:representation, :invalid) unless valid
  end

  def valid_line_string?(geometry)
    geometry.is_a?(Hash) && geometry.keys.map(&:to_s).sort == %w[coordinates type] && geometry["type"] == "LineString" &&
      geometry["coordinates"].is_a?(Array) && geometry["coordinates"].length >= 2 && geometry["coordinates"].all? { |point| valid_coordinate?(point) }
  end

  def valid_coordinate?(point)
    point.is_a?(Array) && point.length == 2 &&
      point[0].is_a?(Numeric) && point[1].is_a?(Numeric) &&
      point[0].to_f.finite? && point[1].to_f.finite? &&
      point[0].between?(-180, 180) && point[1].between?(-90, 90)
  end

  def validate_chart(chart)
    valid = chart.is_a?(Array) && chart.all? do |point|
      point.is_a?(Hash) && point.keys.map(&:to_s).all? { |key| %w[distance elapsed_time elevation].include?(key) } &&
        point.values.all? { |value| value.nil? || value.is_a?(Numeric) }
    end
    errors.add(:representation, :invalid) unless valid
  end

  def validate_location(location)
    valid = location.is_a?(Hash) && location.keys.map(&:to_s).sort == %w[latitude longitude] &&
      valid_coordinate?([ location["longitude"], location["latitude"] ])
    errors.add(:representation, :invalid) unless valid
  end

  def valid_timestamp?(value)
    Time.iso8601(value)
    true
  rescue ArgumentError, TypeError
    false
  end
end
