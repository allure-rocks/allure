# frozen_string_literal: true

class WorkoutPublication < ApplicationRecord
  include HasShortId

  STATUSES = %w[scheduled active deleted].freeze
  # A scheduled publication is a frozen snapshot that has not been shared yet:
  # nothing local or federated refers to it until activation. Cancellation goes
  # straight to the terminal `deleted` state without any Delete activity.
  ALLOWED_TRANSITIONS = {
    "scheduled" => %w[active deleted].freeze,
    "active" => %w[deleted].freeze,
    "deleted" => [].freeze
  }.freeze
  # Audiences from the narrowest to the widest (docs/dev/PUBLISHING.md): a
  # reader entitled to several live publications of one workout is served the
  # first of them. A future group audience goes before `followers`.
  AUDIENCE_PRECEDENCE = %w[followers public].freeze
  # The SQL twin of `audience_rank`, written out so it stays a literal; a
  # model spec keeps it in step with AUDIENCE_PRECEDENCE.
  AUDIENCE_RANK_SQL = "CASE workout_publications.audience WHEN 'followers' THEN 0 WHEN 'public' THEN 1 ELSE 2 END"
  SERVED_ORDER_SQL = "workout_publications.workout_id, #{AUDIENCE_RANK_SQL}, workout_publications.id"
  # The frozen profile shares the route and the route was not redacted: a
  # board or reach computation never reveals a passage whose publication
  # hides where it went (docs/dev/SEGMENTS.md).
  ROUTE_SHARED_SQL = <<~SQL.squish
    workout_publications.profile_snapshot -> 'settings' ->> 'route' = 'true'
    AND COALESCE(workout_publications.route_metadata ->> 'redacted', 'false') <> 'true'
  SQL
  IMMUTABLE_ATTRIBUTES = %i[
    uuid actor_id workout_id publishing_profile_id object_uri profile_snapshot
    privacy_zone_fingerprint route_metadata representation filtered_points_count has_route published_at
    sanitized_gpx_blob_id sanitized_route_image_blob_id sanitized_route_image_dark_blob_id
  ].freeze

  belongs_to :actor, inverse_of: :workout_publications
  belongs_to :workout, inverse_of: :workout_publications, optional: true
  belongs_to :publishing_profile, inverse_of: :workout_publications, optional: true
  has_many :outbox_events,
           class_name: "FederationOutboxEvent",
           foreign_key: :workout_publication_id,
           inverse_of: :workout_publication,
           dependent: :restrict_with_exception

  # The photos frozen at publish time (docs/dev/PHOTOS.md).
  has_many :photos, -> { order(:position) }, class_name: "WorkoutPublicationPhoto",
                                              inverse_of: :workout_publication, dependent: :destroy
  has_one_attached :gpx, dependent: :purge_later
  has_one_attached :route_image, dependent: :purge_later
  has_one_attached :route_image_dark, dependent: :purge_later

  attr_readonly(*IMMUTABLE_ATTRIBUTES)

  scope :active, -> { where(status: "active") }
  scope :deleted, -> { where(status: "deleted") }
  # Publications still inside their safety delay, invisible to every reader.
  scope :scheduled, -> { where(status: "scheduled") }
  scope :live, -> { where(status: %w[active scheduled]) }
  scope :due_for_activation, ->(now = Time.current) { scheduled.where(scheduled_for: ..now) }
  scope :narrowest_first, -> { order(Arel.sql(AUDIENCE_RANK_SQL), :id) }
  # The audience scopes read the generated `audience` column, which is derived
  # from the frozen snapshot and can never disagree with it.
  scope :publicly_visible, -> { active.where(audience: "public") }
  scope :followers_visible, -> { active.where(audience: "followers") }
  scope :route_shared, -> { where(ROUTE_SHARED_SQL) }
  # The active publications a signed-in reader may discover on a profile. It
  # mirrors Workouts::PublicationPolicy's browser branch: a public publication
  # serves every account, a followers publication serves the owner and accepted
  # local followers whatever the federation switches say, and a tombstoned or
  # absent viewer fails closed. `publicly_visible` stays the audience-blind
  # public set used by federation and operator aggregates.
  # An account whose deletion is scheduled is deactivated for its window: its
  # publications are hidden locally and refused on the wire until the purge
  # withdraws them (docs/dev/ACCOUNT.md).
  scope :of_available_owners, -> {
    where.not(actor_id: Actor.joins(:user).where.not(users: { deletion_scheduled_at: nil }).select(:id))
  }

  scope :visible_to, ->(user) {
    next none if user.nil?
    next none if user.actor&.tombstoned?
    owner_visible = followers_visible.where(workout_id: Workout.where(user_id: user.id).select(:id))
    visible = publicly_visible.or(owner_visible)
    next visible.of_available_owners unless user.actor

    follower_visible = followers_visible.where(
      actor_id: Following.accepted_following_of(user.actor).select(:followed_actor_id)
    )
    visible.or(follower_visible).of_available_owners
  }

  # `visible_to` kept to one publication per workout: the narrowest audience,
  # the one the reader is served (docs/dev/PUBLISHING.md).
  scope :served_to, ->(user) {
    where(id: visible_to(user).unscope(:order)
      .select(Arel.sql("DISTINCT ON (workout_publications.workout_id) workout_publications.id"))
      .order(Arel.sql(SERVED_ORDER_SQL)))
  }

  before_validation :assign_publication_identity, on: :create
  before_validation :snapshot_profile_settings, on: :create

  validates :uuid, format: { with: Allure::ShortId::UUID_PATTERN }, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :object_uri, presence: true
  validates :privacy_zone_fingerprint,
            format: { with: /\A\h{64}\z/ }
  validates :filtered_points_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :has_route, inclusion: { in: [ true, false ] }
  validates :published_at, presence: true
  validates :scheduled_for, presence: true, if: :scheduled?
  validates :actor, presence: true
  validate :live_audience_is_free, if: -> { active? || scheduled? }
  validates :deleted_at, presence: true, if: :deleted?
  validates :deleted_at, absence: true, if: -> { active? || scheduled? }
  validate :profile_snapshot_is_an_object
  validate :profile_snapshot_has_policy
  validate :route_metadata_is_an_object
  validate :representation_is_an_object
  validate :sanitized_blob_content_types
  validate :actor_is_retained_local_actor
  validate :workout_presence_matches_status
  validate :profile_belongs_to_workout_owner
  validate :object_uri_matches_identity, on: :create
  validate :status_transition_is_allowed, on: :update
  validate :profile_is_present_on_create, on: :create

  def self.object_uri_for(uuid)
    Allure::Federation.config.workout_publication_uri(Allure::ShortId.encode(uuid))
  end

  def self.audience_rank(audience) = AUDIENCE_PRECEDENCE.index(audience) || AUDIENCE_PRECEDENCE.length

  # Sorts publications from the narrowest audience to the widest.
  def self.by_precedence(publications) = publications.sort_by { |publication| [ audience_rank(publication.audience), publication.id.to_i ] }

  def active? = status == "active"
  def scheduled? = status == "scheduled"
  def deleted? = status == "deleted"
  # The stored column is generated from the snapshot; an unsaved row reads the
  # snapshot itself.
  def audience = self[:audience] || (profile_snapshot["audience"] if profile_snapshot.is_a?(Hash))
  def profile_settings = profile_snapshot.fetch("settings", {})
  def track = representation["track"]
  def metrics = representation.fetch("metrics", {})
  def publication_title = representation["title"]
  def publication_description = representation["description"]

  # Comments are open while the snapshot's profile allowed them and the owner
  # has not closed the thread live (docs/dev/COMMENTS.md).
  def comments_closed_by_profile? = representation["comments_closed"] == true
  def comments_open? = !comments_closed_by_profile? && workout.present? && workout.comments_closed_at.nil?
  def publication_started_at = representation["started_at"]
  def publication_sport_slug = representation["sport_slug"]

  def sanitized_attachment(name)
    raise ArgumentError, "unknown publication attachment" unless %i[gpx route_image route_image_dark].include?(name.to_sym)

    expected_blob_id = public_send("sanitized_#{name}_blob_id")
    attachment = public_send(name)
    return unless expected_blob_id.present? && attachment.attached?
    return unless attachment.blob.id == expected_blob_id

    attachment
  end

  # The sanitized route image variant matching the requested theme, with the
  # other variant as fallback so a themed URL never 404s while one image is
  # attached (DESIGN.md §15.4).
  def route_image_variant(theme)
    requested, fallback = if theme.to_s == "dark"
      [ sanitized_attachment(:route_image_dark), sanitized_attachment(:route_image) ]
    else
      [ sanitized_attachment(:route_image), sanitized_attachment(:route_image_dark) ]
    end
    requested || fallback
  end

  def viewable_by?(viewer)
    Workouts::PublicationPolicy.new(
      publication: self,
      principal: Workouts::PublicationPrincipal.browser(viewer)
    ).allowed?
  end

  def viewable_by_actor?(actor)
    Workouts::PublicationPolicy.new(
      publication: self,
      principal: Workouts::PublicationPrincipal.protocol(actor)
    ).allowed?
  end

  def mark_deleted!
    return self if deleted?

    update!(status: "deleted", deleted_at: Time.current)
    workout&.reset_publications
    Participations::RemoteWithdrawal.publication_gone!(self)
    self
  end

  # Leaves the safety delay (the scheduled activation job or the owner's
  # "publish now"). A scheduled publication was never externally visible, so
  # rewriting `published_at` from the planned moment to the actual instant is
  # the controlled immutability exception for this state change, the same class
  # of exception as `attach_sanitized_route_image!`. The transition itself is
  # written through the relation: the row's other attributes were validated at
  # creation and everything except status/published_at stays immutable.
  def activate!(at: Time.current)
    return self unless scheduled?

    activated = false
    with_lock do
      if scheduled?
        self.class.where(id: id).update_all(
          status: "active",
          published_at: at,
          updated_at: at
        )
        activated = true
      end
    end
    return self unless activated

    reload
    workout&.reset_publications
    self
  end

  # The sanitized route image renders asynchronously on the route_images
  # worker. The reference is written once, from nil, once the publication
  # exists; the model's immutability contract still holds afterwards. The
  # relation write is the controlled exception, like outbox payload redaction.
  # Both variants are written the same way.
  def attach_sanitized_route_image!(blob)
    attach_sanitized_route_image_variant!(:route_image, blob)
  end

  def attach_sanitized_route_image_dark!(blob)
    attach_sanitized_route_image_variant!(:route_image_dark, blob)
  end

  def route_image_pending?
    profile_settings["route_image"] == true && sanitized_route_image_blob_id.blank?
  end

  # Snapshots written before the setting existed carry no "basemap" key and keep
  # the historical behaviour: the basemap is present. An explicit key follows
  # the profile form, where an unchecked boolean is stored as nil.
  def basemap_enabled?
    return true unless profile_settings.key?("basemap")

    profile_settings["basemap"] == true
  end

  def publication_document
    Federation::Serializers::WorkoutNote.new(publication: self, actor:).call
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
    self.published_at ||= scheduled_for || Time.current
  end

  def snapshot_profile_settings
    return unless profile_snapshot.blank? && publishing_profile

    self.profile_snapshot = {
      "audience" => publishing_profile.audience,
      "name" => publishing_profile.name,
      "settings" => publishing_profile.settings.deep_dup
    }
  end

  # One live publication per audience and workout (docs/dev/PUBLISHING.md); the
  # partial unique index is the authority under concurrency.
  def live_audience_is_free
    return if workout_id.blank? || audience.blank?

    taken = self.class.live.where(workout_id:, audience:).where.not(id:).exists?
    errors.add(:workout_id, :taken) if taken
  end

  def profile_snapshot_is_an_object
    errors.add(:profile_snapshot, :invalid) unless profile_snapshot.is_a?(Hash)
  end

  def profile_snapshot_has_policy
    return unless profile_snapshot.is_a?(Hash)

    unless PublishingProfile::AUDIENCES.include?(profile_snapshot["audience"])
      errors.add(:profile_snapshot, :invalid)
    end

    settings = profile_snapshot["settings"]
    unless settings.is_a?(Hash)
      errors.add(:profile_snapshot, :invalid)
      return
    end

    allowed = PublishingProfile::SETTING_KEYS + PublishingProfile::LEGACY_SNAPSHOT_SETTING_KEYS
    errors.add(:profile_snapshot, :invalid) unless settings.keys.map(&:to_s).all? { |key| allowed.include?(key) }
    (PublishingProfile::BOOLEAN_SETTING_KEYS + PublishingProfile::LEGACY_SNAPSHOT_SETTING_KEYS).each do |key|
      errors.add(:profile_snapshot, :invalid) unless settings[key].nil? || settings[key] == true || settings[key] == false
    end
    metrics = settings["metrics"]
    errors.add(:profile_snapshot, :invalid) if metrics && (!metrics.is_a?(Array) || metrics.any? { |metric| !PublishingProfile::METRIC_KEYS.include?(metric.to_s) })
  end

  def route_metadata_is_an_object
    unless route_metadata.is_a?(Hash)
      errors.add(:route_metadata, :invalid)
      return
    end

    if route_metadata["redacted"] == true
      allowed_keys = %w[redacted]
      errors.add(:route_metadata, :invalid) unless route_metadata.keys.map(&:to_s).all? { |key| allowed_keys.include?(key) }
      return
    end

    allowed_keys = %w[bounds segments_count]
    errors.add(:route_metadata, :invalid) unless route_metadata.keys.map(&:to_s).all? { |key| allowed_keys.include?(key) }
    bounds = route_metadata["bounds"]
    errors.add(:route_metadata, :invalid) unless bounds.is_a?(Array) && bounds.length == 4 && bounds.all? { |value| value.is_a?(Numeric) && value.to_f.finite? }
    segments_count = route_metadata["segments_count"]
    errors.add(:route_metadata, :invalid) unless segments_count.is_a?(Integer) && segments_count.positive?
  end

  def representation_is_an_object
    unless representation.is_a?(Hash)
      errors.add(:representation, :invalid)
      return
    end

    allowed_keys = %w[
      title description metrics track chart location sport_slug started_at redacted record_types record_distances
      device commute weather comments_closed photos
    ]
    errors.add(:representation, :invalid) unless representation.keys.map(&:to_s).all? { |key| allowed_keys.include?(key) }
    errors.add(:representation, :invalid) unless representation["sport_slug"].is_a?(String) && representation["sport_slug"].present?
    errors.add(:representation, :invalid) unless representation["started_at"].is_a?(String) && valid_timestamp?(representation["started_at"])
    if representation["redacted"] == true
      errors.add(:representation, :invalid) if representation.keys.map(&:to_s).any? { %w[track chart location photos].include?(_1) }
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
    validate_photos(representation["photos"]) if representation.key?("photos")
  end

  PHOTO_KEYS = %w[id width height caption distance].freeze

  # The frozen photos (docs/dev/PHOTOS.md): an identifier, dimensions, an
  # optional caption and an optional distance along the published route —
  # never a coordinate, a capture time or any EXIF field.
  def validate_photos(photos)
    valid = photos.is_a?(Array) && photos.any? && photos.length <= WorkoutPublicationPhoto::MAX_PER_PUBLICATION &&
      photos.all? do |photo|
        photo.is_a?(Hash) && photo.keys.map(&:to_s).all? { PHOTO_KEYS.include?(it) } &&
          photo["id"].is_a?(String) && photo["id"].present? &&
          photo["width"].is_a?(Integer) && photo["width"].positive? &&
          photo["height"].is_a?(Integer) && photo["height"].positive? &&
          (photo["caption"].nil? || (photo["caption"].is_a?(String) && photo["caption"].present? && photo["caption"].length <= Allure::Photos::Config::MAX_CAPTION)) &&
          (photo["distance"].nil? || (photo["distance"].is_a?(Numeric) && photo["distance"].to_f.finite? && photo["distance"] >= 0))
      end
    errors.add(:representation, :invalid) unless valid
  end

  def validate_record_tokens(value, allowlist)
    return if value.nil?

    valid = value.is_a?(Array) && value.length <= 32 &&
      value.uniq.length == value.length &&
      value.all? { |token| token.is_a?(String) && allowlist.include?(token) }
    errors.add(:representation, :invalid) unless valid
  end

  # The device string is a free-form display value, never a payload: it is a
  # bounded non-blank string when the profile shares it.
  def validate_device(value)
    return if value.nil?

    max = Allure::Federation::Privacy::SanitizedPublicationBuilder::MAX_DEVICE_LENGTH
    valid = value.is_a?(String) && value.present? && value.length <= max
    errors.add(:representation, :invalid) unless valid
  end

  # The commute flag is presence-only in a snapshot: the profile either shares
  # the fact or the key is absent. A stored `false` is therefore invalid.
  def validate_commute(value)
    return if value.nil?

    errors.add(:representation, :invalid) unless value == true
  end

  # A profile that disabled comments freezes `comments_closed: true` into the
  # snapshot; absence means open (docs/dev/COMMENTS.md).
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
      geometry = feature.is_a?(Hash) && feature.keys.map(&:to_s).sort == %w[geometry properties type] && feature["type"] == "Feature"
      geometry && feature["properties"].is_a?(Hash) && feature["properties"].keys.map(&:to_s) == [ "segment_index" ] &&
        feature["properties"]["segment_index"].is_a?(Integer) && valid_line_string?(feature["geometry"])
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

    return if workout.blank?
    return if actor.user_id == workout.user_id

    errors.add(:actor, :invalid)
  end

  def workout_presence_matches_status
    if (active? || scheduled?) && workout_id.blank?
      errors.add(:workout, :blank)
    elsif deleted? && workout_id.present? && workout.blank?
      errors.add(:workout, :invalid)
    end
  end

  def profile_belongs_to_workout_owner
    return if publishing_profile.blank?
    return if actor.blank? && workout.blank?

    owner_id = workout&.user_id || actor&.user_id
    return if owner_id.present? && publishing_profile.user_id == owner_id

    errors.add(:publishing_profile, :invalid)
  end

  def profile_is_present_on_create
    errors.add(:publishing_profile, :blank) if publishing_profile.blank?
  end

  def object_uri_matches_identity
    return unless uuid.to_s.match?(Allure::ShortId::UUID_PATTERN)

    errors.add(:object_uri, :invalid) unless object_uri == self.class.object_uri_for(uuid)
  end

  def status_transition_is_allowed
    return unless will_save_change_to_status?

    allowed = ALLOWED_TRANSITIONS.fetch(status_in_database.to_s, [])
    errors.add(:status, :invalid) unless allowed.include?(status)
  end
end
