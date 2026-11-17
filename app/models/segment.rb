# frozen_string_literal: true

class Segment < ApplicationRecord
  include HasShortId
  include HasRouteImage

  KINDS = %w[segment route loop].freeze
  PLACE_STATUSES = %w[pending ready unavailable failed].freeze
  ELEVATION_SOURCES = %w[device dem].freeze
  ELEVATION_STATUSES = %w[ready unavailable failed].freeze

  belongs_to :user
  belongs_to :sport, optional: true
  belongs_to :source_workout, class_name: "Workout", optional: true, inverse_of: :source_segments
  belongs_to :remote_segment, optional: true, inverse_of: :local_copies
  has_many :segment_efforts, dependent: :destroy, inverse_of: :segment
  has_many :segment_opt_outs, dependent: :destroy, inverse_of: :segment
  has_many :segment_publications, dependent: :nullify, inverse_of: :segment
  # The recurring-route suggestions this route accepted (docs/dev/SEGMENTS.md
  # §7.7). A deleted route keeps the suggestion accepted: the owner's decision
  # stands and the suggestion never returns.
  has_many :route_suggestions, dependent: :nullify, inverse_of: :segment
  has_one :active_publication,
          -> { active },
          class_name: "SegmentPublication",
          inverse_of: :segment

  # Courses a viewer may read beyond their own: public ones plus followers-only
  # ones whose owner the viewer follows (docs/dev/SEGMENTS.md). Private
  # courses are never readable here; callers scope ownership when needed.
  scope :readable_by, ->(viewer) {
    followed_owner_ids = if viewer&.actor
      Following.local_user_ids_followed_by(viewer.actor)
    else
      User.none.select(:id)
    end

    shared = where.not(visibility: "private")
    shared
      .where(visibility: "public")
      .or(shared.where(user_id: viewer&.id))
      .or(shared.where(user_id: followed_owner_ids))
      .where.not(user_id: User.where.not(deletion_scheduled_at: nil).select(:id))
  }

  # Courses the viewer has a trace on: at least one matched effort of their own.
  scope :run_by, ->(viewer) {
    viewer ? where(id: viewer.segment_efforts.select(:segment_id)) : none
  }

  # Every course the viewer may see, their own private ones included: the
  # discover map is viewer-scoped, so nothing here is ever exposed to a
  # non-owner (docs/dev/SEGMENTS.md). `readable_by` already carries the
  # viewer's own public and followers-only courses and the followed owners'.
  scope :visible_to, ->(viewer) {
    viewer ? readable_by(viewer).or(where(user_id: viewer.id)) : none
  }

  validates :uuid, uniqueness: true, allow_nil: true
  validates :kind, :name, :geom, :start_point, :end_point, :bounds, :distance, :signature,
            :match_tolerance_meters, :visibility, :matcher_version,
            presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :name, length: { in: 1..120 }
  validates :description, length: { maximum: 2_000 }, allow_nil: true
  validates :distance, numericality: { greater_than: 0 }
  validates :ascent, :descent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_elevation, :max_elevation, :average_grade, numericality: true, allow_nil: true
  validates :match_tolerance_meters,
            numericality: { only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 100 }
  validates :visibility, inclusion: { in: Allure::VisibilityLevel::LEVELS }
  validates :place_status, inclusion: { in: PLACE_STATUSES }
  validates :elevation_source, inclusion: { in: ELEVATION_SOURCES }
  validates :elevation_status, inclusion: { in: ELEVATION_STATUSES }, allow_nil: true
  validates :place_name, length: { maximum: 120 }, allow_nil: true
  validates :active, inclusion: { in: [ true, false ] }
  validates :efforts_count, :athletes_count, :matcher_version, :route_image_version,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source_start_index, :source_end_index,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :bounds_have_four_values
  validate :signature_has_64_values
  validate :geometry_has_two_points
  validate :only_segments_are_shareable
  validate :shared_corridor_acknowledged
  validate :active_publication_allows_visibility

  # A detected loop is derived from a single workout and matched inline by
  # `Segments::MatchWorkoutJob`; it never backfills other workouts.
  after_create_commit :enqueue_backfill, unless: -> { kind == "loop" }
  # The owner image is derived media: created missing, rendered once on the
  # dedicated route_images worker, then re-rendered only by the sweeps
  # (docs/dev/DERIVATIONS.md).
  after_create_commit :enqueue_route_image
  # The nearby place is geocoded once from the course midpoint: the geometry
  # never changes afterwards (docs/dev/SEGMENTS.md).
  after_create_commit :enqueue_place_geocoding
  # The terrain service's profile replaces the device's when it is available
  # and allowed; a course that turns public becomes allowed
  # (docs/dev/ELEVATION.md).
  after_commit :enqueue_terrain_elevation, on: %i[create update],
                                           if: -> { previously_new_record? || saved_change_to_visibility? }

  # Whether `viewer` (a signed-in User) may see this segment's
  # leaderboard. After the docs/dev/SEGMENTS.md merge the board follows the
  # course visibility: the same predicate, so nobody ever reaches a board
  # whose course they cannot read. Every denial surfaces as 404 via the
  # controllers, never 403.
  def leaderboard_viewable_by?(viewer) = viewable_by?(viewer)

  # Whether `viewer` (a signed-in User) may see the course itself: name,
  # description, metrics, map, and its board. Viewing requires an account
  # (docs/dev/ACCESS.md): a public course is not served to `nil`. Every
  # denial surfaces as 404 via the controllers, never 403.
  def viewable_by?(viewer)
    return true if viewer == user
    # A deactivated owner's courses are hidden for the deletion window
    # (docs/dev/ACCOUNT.md).
    return false if user.deletion_scheduled?

    case visibility
    when "public" then viewer.present?
    when "followers_only" then accepted_follower?(viewer)
    else false
    end
  end

  # Whether `user` opted out of this segment's board (docs/dev/SEGMENTS.md).
  def opted_out?(user)
    return false if user.blank?

    segment_opt_outs.exists?(user_id: user.id)
  end

  # Every athlete with a recorded effort, published or not: the counter of a
  # private course, which only its owner reads. A shared course shows each
  # viewer their own board's count instead (`Segments::Listing.participants_count`,
  # docs/dev/SEGMENTS.md). A credited effort does not count: its athlete did
  # not record the course (docs/dev/SHARED-ACTIVITIES.md).
  def participants_count
    segment_efforts.joins(:workout).merge(Workout.recordings).distinct.count("segment_efforts.user_id")
  end

  # Whether the course may be distributed at all: routes and loops never are,
  # and a private course has no audience to publish to.
  def shareable? = kind == "segment" && visibility != "private"

  # Whether the owner renamed this course. A renamed loop is the identity the
  # owner chose: the reconciliation elects it and the orphan sweep spares it
  # (docs/dev/SEGMENTS.md).
  def renamed? = renamed_at.present?

  # Detects an active publication that no longer matches the represented
  # attributes. Any listed edit marks it stale and offers republishing; nothing
  # is emitted automatically.
  def publication_stale?
    publication = active_publication
    publication.present? && publication.source_fingerprint != publication_fingerprint
  end

  # Canonical digest of every attribute the federated course carries; the
  # publication stores it at creation time.
  def publication_fingerprint
    Digest::SHA256.hexdigest(
      JSON.generate(
        name:,
        description:,
        sport_id:,
        visibility:,
        match_tolerance_meters:,
        active:,
        geom: geom&.to_s
      )
    )
  end

  # The board one viewer reads (docs/dev/SEGMENTS.md): the athletes whose
  # publication the viewer may read with the route shared, who did not opt
  # out and whose privacy zones stay clear of the corridor — best per athlete
  # and sport, ordered by time. `scope: "following"` keeps the accounts the
  # viewer follows and the viewer. The rendering layer decides names versus
  # aliases. Eligibility is derived on read by `Segments::Listing`.
  def leaderboard_efforts(viewer:, scope: "everyone")
    best_per_athlete(
      Segments::Listing.for_segment(self, viewer:, scope:)
        .includes(:user, :workout, :sport).order(:elapsed_time, :started_at, :id)
    )
  end

  # The board split into one ranking per sport, in catalog order: a multi-sport
  # segment reads as several individual boards, a single-sport segment keeps one
  # plain section. Shared by the standalone board page and its detail preview.
  def leaderboard_sections(viewer:, scope: "everyone")
    leaderboard_efforts(viewer:, scope:).group_by(&:sport).sort_by { |sport, _rows| sport.position }
  end

  private

  def bounds_have_four_values
    errors.add(:bounds, :invalid) unless bounds.is_a?(Array) && bounds.length == 4
  end

  def signature_has_64_values
    errors.add(:signature, :invalid) unless signature.is_a?(Array) && signature.length == 64
  end

  def geometry_has_two_points
    errors.add(:geom, :invalid) if geom && (!geom.respond_to?(:num_points) || geom.num_points < 2)
  end

  # Routes and loops are never shared; only `kind: "segment"` leaves private.
  def only_segments_are_shareable
    return if kind == "segment"

    errors.add(:visibility, :invalid) if visibility.present? && visibility != "private"
  end

  # A course whose corridor intersects one of the owner's active privacy zones
  # may only be shared after the owner explicitly acknowledged it. Zones are
  # not subtracted from a segment, so this is a consent gate
  # (docs/dev/SEGMENTS-FEDERATION.md).
  def shared_corridor_acknowledged
    return if visibility == "private"
    return if privacy_zone_acknowledged_at.present?
    return unless geom.present? && user&.persisted?

    errors.add(:base, :corridor_privacy_zone) if Segments::CorridorPreflight.intersects?(self)
  end

  # A live publication must never outlive the visibility that justified it:
  # while one is active, the course cannot become more restrictive than its
  # audience (docs/dev/SEGMENTS-FEDERATION.md).
  def active_publication_allows_visibility
    publication = active_publication
    return if publication.blank?

    allowed = publication.audience_public? ? visibility == "public" : visibility != "private"
    errors.add(:visibility, :published_restriction) unless allowed
  end

  def accepted_follower?(viewer)
    return false if viewer.nil? || viewer.actor.nil? || user.actor.nil?

    Following.accepted_between(follower_actor: viewer.actor, followed_actor: user.actor).exists?
  end

  def enqueue_backfill
    Segments::BackfillSegmentJob.perform_later(self)
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, segment_id: id })
  end

  def enqueue_route_image
    Segments::RenderRouteImageJob.perform_later(self)
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, segment_id: id })
  end

  def enqueue_place_geocoding
    Segments::GeocodePlaceJob.perform_later(self)
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, segment_id: id })
  end

  def enqueue_terrain_elevation
    Segments::ApplyTerrainElevationJob.enqueue_if_eligible(self)
  end

  def best_per_athlete(ordered_efforts)
    ordered_efforts.group_by { |effort| [ effort.sport_id, effort.user_id ] }.map do |_, efforts|
      efforts.min_by { |effort| [ effort.elapsed_time, effort.started_at, effort.id ] }
    end.sort_by { |effort| [ effort.elapsed_time, effort.started_at, effort.id ] }
  end
end
