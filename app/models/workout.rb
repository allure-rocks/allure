# frozen_string_literal: true

class Workout < ApplicationRecord
  include HasShortId
  include HasRouteImage

  attribute :analysis_version, :integer, default: -> { Allure::Gpx::Analyzer::VERSION }
  # A freshly imported workout already carries current facts (its device, its
  # detected sport, its venue were resolved from this very file).
  attribute :import_detection_version, :integer, default: -> { Workouts::ImportDetection::VERSION }

  # Mirrors the workouts_import_format check constraint. Allure::ImportFormat
  # maps each key to its parser, extension, and storage content type.
  IMPORT_FORMATS = %w[gpx fit tcx kml].freeze

  # The analysis source of the elevation profile: the recording device or the
  # configured DEM service (docs/dev/ELEVATION.md).
  ELEVATION_SOURCES = %w[device dem].freeze

  # A recording comes from an imported file; a credit row stands for a
  # confirmed credit participation and carries only the credited metric set,
  # no geometry (docs/dev/SHARED-ACTIVITIES.md); a manual entry carries the figures its
  # owner typed in, no file and no geometry (docs/dev/MANUAL-ENTRY.md). Mirrors
  # workouts_origin.
  ORIGINS = %w[import credit manual].freeze

  # Where the title came from (docs/dev/AI.md): the import form, the track's own
  # name, or the member. Only the first two let the summary card propose one.
  TITLE_SOURCES = %w[default file owner].freeze

  # The bounds a hand-typed figure must fall within (docs/dev/MANUAL-ENTRY.md):
  # SI, as persisted. A recording's figures are measured, never checked here.
  MANUAL_LIMITS = {
    duration: 1..(7 * 86_400),
    moving_time: 1..(7 * 86_400),
    distance: 0..2_000_000,
    ascent: 0..20_000,
    average_heart_rate: 20..250,
    max_heart_rate: 20..250,
    calories: 0..20_000,
    average_power: 1..3_000
  }.freeze

  belongs_to :user
  has_many :photos, -> { order(:position, :id) }, class_name: "WorkoutPhoto", dependent: :destroy, inverse_of: :workout
  belongs_to :sport
  # Imported from a remote provider under `external_id` (docs/dev/REMOTE-IMPORTS.md).
  belongs_to :import_connection, optional: true
  # Recording segments: one per contiguous GPX <trkseg>, or per run of FIT
  # records between timer stop_all events. Deliberately not named `segments`:
  # that word belongs to the reusable course portions specified in
  # docs/dev/SEGMENTS.md.
  has_many :track_segments,
           -> { order(:position) },
           dependent: :destroy,
           inverse_of: :workout
  has_many :segment_efforts, dependent: :destroy, inverse_of: :workout
  # Standard-distance best efforts, rebuilt from the track on import and
  # reanalysis; effort records survive their source workout through a
  # recompute (workout_id nullify), mirroring `Record`.
  has_many :best_efforts, dependent: :destroy, inverse_of: :workout
  has_many :effort_records, dependent: :nullify, inverse_of: :workout
  has_many :records, dependent: :nullify, inverse_of: :workout
  has_many :laps,
           -> { order(:number) },
           dependent: :destroy,
           inverse_of: :workout
  # Derived smart laps: detected loops, routes, pauses, and climbs. Rebuilt
  # deterministically from the track and existing efforts, never federated.
  has_many :detected_laps,
           -> { order(:start_distance, :id) },
           dependent: :destroy,
           inverse_of: :workout
  has_and_belongs_to_many :equipments, join_table: "workout_equipments"
  has_many :reactions, inverse_of: :workout, dependent: :destroy
  # The thread this instance hosts for the workout's publications
  # (docs/dev/COMMENTS.md): it belongs to the workout, not to one publication
  # identity, so republishing keeps it.
  has_many :comments, inverse_of: :workout, dependent: :delete_all
  # Confirmed shared activities (docs/dev/SHARED-ACTIVITIES.md). This workout is the source
  # of each row; `participant_links` are the rows where another account's
  # recording names this workout as its source. Never federated in v1.
  has_many :workout_participations, dependent: :destroy, inverse_of: :workout
  has_many :participant_links,
           class_name: "WorkoutParticipation",
           foreign_key: :participant_workout_id,
           dependent: :destroy,
           inverse_of: :participant_workout
  has_many :workout_publications, dependent: :nullify, inverse_of: :workout
  has_one :toponymy,
          class_name: "WorkoutToponymy",
          dependent: :destroy,
          inverse_of: :workout
  # Every recorded place derived from the toponymy: the indexable source of the
  # owner's place filter and autocomplete. Never published or federated.
  has_many :place_names,
           class_name: "WorkoutPlaceName",
           dependent: :delete_all,
           inverse_of: :workout
  # Terrain elevation fetched for a workout without a recorded profile, or
  # chosen by the owner instead of it (docs/dev/ELEVATION.md).
  has_one :elevation,
          class_name: "WorkoutElevation",
          dependent: :destroy,
          inverse_of: :workout
  # Historical weather along the route, for an account that consented
  # (docs/dev/WEATHER.md). Owner-only except the summary a profile may share.
  has_one :weather,
          class_name: "WorkoutWeather",
          dependent: :destroy,
          inverse_of: :workout
  # The recording's heart-rate histogram (docs/dev/HEART-RATE.md). Owner-only.
  has_one :heart_rate,
          class_name: "WorkoutHeartRate",
          dependent: :delete,
          inverse_of: :workout
  # The assistant's summary of this workout (docs/dev/AI.md). Owner-only: it
  # never enters a publication, a federation object or a programmatic answer.
  has_one :assistant_summary,
          class_name: "WorkoutSummary",
          dependent: :destroy,
          inverse_of: :workout
  # At most one live publication per audience (docs/dev/PUBLISHING.md), listed
  # from the narrowest audience to the widest. A reader is served the first
  # one their entitlements allow (Workouts::PublicationResolver).
  has_many :active_publications,
           -> { active.narrowest_first },
           class_name: "WorkoutPublication",
           inverse_of: :workout
  # Frozen snapshots inside their publishing delay (docs/dev/DELAYED-PUBLISHING.md).
  # Invisible to every reader until they activate; the owner can cancel,
  # reschedule, or publish them now.
  has_many :scheduled_publications,
           -> { scheduled.narrowest_first },
           class_name: "WorkoutPublication",
           inverse_of: :workout
  # The automatic publications an import scheduled (docs/dev/AUTO-PUBLISHING.md):
  # one per audience, owner-only bookkeeping, never published or federated.
  has_many :auto_publications,
           class_name: "WorkoutAutoPublication",
           dependent: :delete_all,
           inverse_of: :workout
  has_many :source_segments,
           class_name: "Segment",
           foreign_key: :source_workout_id,
           inverse_of: :source_workout
  # Recurring-route suggestions naming this recording (docs/dev/SEGMENTS.md).
  # Owner-only derived bookkeeping: deleting the workout drops its membership,
  # and a suggestion left without a member disappears.
  has_many :route_suggestion_workouts, dependent: :destroy, inverse_of: :workout
  has_one_attached :original_file, dependent: :purge_later
  # A credit row's source while attached (the foreign key nullifies it when the
  # source is deleted) and the source's owner, kept after detachment for the
  # « Avec @X » badge (docs/dev/SHARED-ACTIVITIES.md).
  belongs_to :credited_from, class_name: "Workout", foreign_key: :credited_from_workout_id,
                             optional: true, inverse_of: :credit_rows
  belongs_to :credited_by, class_name: "Actor", foreign_key: :credited_by_actor_id, optional: true
  has_many :credit_rows, class_name: "Workout", foreign_key: :credited_from_workout_id,
                         inverse_of: :credited_from
  # A credit confirmed for an invitation from another instance: its figures
  # come from the received note, it has no local source (docs/dev/SHARED-ACTIVITIES.md).
  belongs_to :remote_participation, optional: true, inverse_of: :credit_row

  validates :uuid, uniqueness: true, allow_nil: true
  validates :origin, inclusion: { in: ORIGINS }
  validates :title_source, inclusion: { in: TITLE_SOURCES }
  validates :source_digest, format: { with: /\A\h{64}\z/ }, allow_nil: true
  validates :started_at, presence: true
  validates :title, length: { maximum: 255 }, allow_nil: true
  validates :description, length: { maximum: 10_000 }, allow_nil: true
  validates :notes, length: { maximum: 500 }, allow_nil: true
  validates :duration, :moving_time, :pause_time,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :analysis_version, numericality: { only_integer: true, greater_than: 0 }
  validates :import_detection_version, :route_image_version,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :points_count, numericality: { only_integer: true, greater_than_or_equal_to: 2 }, if: :recording?
  validates :distance, :ascent, :descent, :average_speed,
            numericality: { greater_than_or_equal_to: 0 }
  validates :max_speed, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_pace, :best_pace, :calories, :grade_adjusted_pace,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :average_heart_rate, :max_heart_rate, :average_cadence, :max_cadence,
            :average_power, :max_power,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :import_format, inclusion: { in: IMPORT_FORMATS }, if: :recording?
  validates :credited_by, presence: true, if: :credit?
  validates :elevation_filter, inclusion: { in: %w[barometric gps dem] }, allow_nil: true
  validates :recorded_elevation, inclusion: { in: [ true, false ] }
  validates :commute, inclusion: { in: [ true, false ] }
  validates :photo_time_offset_seconds, numericality: { only_integer: true, in: -50_400..50_400 }
  validates :elevation_source, inclusion: { in: ELEVATION_SOURCES }
  validates :elevation_source_requested, inclusion: { in: ELEVATION_SOURCES }, allow_nil: true
  validate :duration_components_are_consistent
  validate :bounds_have_four_values
  validate :geometry_columns_are_consistent, if: :recording?
  validate :places_are_an_array
  validate :manual_figures_are_plausible, if: :manual?

  scope :newest_first, -> { order(started_at: :desc, id: :desc) }
  scope :recordings, -> { where(origin: "import") }
  scope :credit_rows_only, -> { where(origin: "credit") }
  scope :manual_entries, -> { where(origin: "manual") }
  # The owner's own activities: what they recorded and what they typed in. A
  # credit row is someone else's recording and is never edited in bulk.
  scope :authored, -> { where(origin: %w[import manual]) }
  # Recordings the geometry-driven derivations may touch: the ones with a
  # track (docs/dev/NO-GPS.md). A positionless recording has no map, no route
  # image, no toponymy and no segment matching.
  scope :positioned, -> { recordings.where.not(start_point: nil) }
  scope :unpositioned, -> { recordings.where(start_point: nil) }
  # The workouts a signed-in viewer may discover on a profile: their active
  # public publications for every account, plus followers publications for the
  # owner and accepted local followers while restricted federation is enabled
  # (Workouts::PublicationPolicy).
  scope :published_visible_to, ->(user) {
    where(id: WorkoutPublication.visible_to(user).select(:workout_id))
  }
  # Recordings whose recorded duration reaches the given moment, whatever
  # their start (the co-presence window's overlap test, docs/dev/SHARED-ACTIVITIES.md).
  scope :ending_at_or_after, ->(time) {
    where("workouts.started_at + make_interval(secs => workouts.duration) >= ?", time)
  }
  # Closest start first, the oldest row on a tie: the order the recording
  # picker offers same-outing recordings in (docs/dev/SHARED-ACTIVITIES.md).
  scope :ordered_by_start_proximity_to, ->(time) {
    order(
      Arel.sql(sanitize_sql_array([ "ABS(EXTRACT(EPOCH FROM (workouts.started_at - ?::timestamp)))", time ])),
      :id
    )
  }

  # Source columns for the seven personal-record types. A change to any of
  # these (or the sport) refreshes the owner's records for the affected scope.
  RECORD_SOURCE_COLUMNS = %i[started_at average_pace average_speed best_pace distance ascent moving_time max_speed contested_metrics].freeze

  # Records recompute inline (not in a job) so the owner sees correct values
  # on the post-save redirect. A failed recompute reports through Rails.error
  # and never rolls back the user's workout.
  after_commit :recompute_records_on_create, on: :create
  after_commit :recompute_records_on_update, on: :update, if: :records_relevant_change?
  after_commit :recompute_records_on_destroy, on: :destroy

  # Equipment totals decrement before the join rows cascade away. A failure
  # reports but never blocks the user's delete; `refresh` repairs drift.
  before_destroy :decrement_equipment_totals
  # The efforts cascade with the workout, so the segments they sat on are
  # captured first (prepended ahead of the `dependent: :destroy` callbacks) and
  # refreshed after commit (docs/dev/SHARED-ACTIVITIES.md).
  before_destroy :capture_effort_segment_ids, prepend: true
  after_commit :refresh_effort_segments, on: :destroy

  # Credit rows (docs/dev/SHARED-ACTIVITIES.md). A source's change reaches its
  # attached credit rows; deleting a source detaches and keeps them; deleting
  # a credit row withdraws its participation so it is never recreated. Both
  # run ahead of the `dependent: :destroy` callbacks, while the
  # participations still exist.
  after_commit :sync_credit_rows, on: :update, if: :credit_sync_relevant?
  before_destroy :detach_credit_rows, prepend: true, if: :recording?
  before_destroy :withdraw_credit_participation, prepend: true, if: :credit?
  after_commit :notify_detached_credits, on: :destroy
  after_commit :enqueue_remote_withdrawal, on: :destroy
  # The reactions cascade with the workout; their digest has nothing left to
  # tell (docs/dev/NOTIFICATIONS.md).
  after_destroy :withdraw_reaction_digest
  after_commit :diff_equipment_totals, on: :update,
    if: -> { saved_change_to_distance? || saved_change_to_moving_time? }

  # Workouts a viewer may see: their own plus active public publications.
  # Viewing requires an account (docs/dev/ACCESS.md), so `nil` sees nothing.
  def self.visible_to(user)
    return none unless user

    where(user:).or(where(id: WorkoutPublication.publicly_visible.select(:workout_id)))
  end

  # The audiences of the live publications, active or scheduled: a new
  # publication can only take another one (docs/dev/PUBLISHING.md).
  def live_audiences
    (active_publications.map(&:audience) + scheduled_publications.map(&:audience)).uniq
  end

  def active_publication_for(audience) = active_publications.find { |publication| publication.audience == audience }

  def scheduled_publication_for(audience) = scheduled_publications.find { |publication| publication.audience == audience }

  def reset_publications
    association(:active_publications).reset
    association(:scheduled_publications).reset
    self
  end

  def viewable_by?(viewer, level: :workout)
    return true if viewer == user

    publication = Workouts::PublicationResolver.new(workout: self, user: viewer).call
    resource = case level.to_sym
    when :workout then :workout
    when :analysis then :analysis
    when :map then :map
    when :media then :media
    else
      raise ArgumentError, "unknown workout visibility level: #{level.inspect}"
    end
    Workouts::PublicationPolicy.new(
      publication:,
      principal: Workouts::PublicationPrincipal.browser(viewer)
    ).allowed?(resource:)
  end

  def recording? = origin == "import"
  def credit? = origin == "credit"
  def manual? = origin == "manual"
  # The owner's own activity, recorded or typed in, as opposed to a credit row.
  def authored? = recording? || manual?
  # A credit row whose source was deleted: frozen, never synced again. A
  # local credit is detached once its source is gone; a remote one, which
  # never has a local source, once its note is deleted (`credit_detached_at`).
  def credit_detached?
    credit? && (credit_detached_at.present? || (credited_from_workout_id.nil? && remote_participation_id.nil?))
  end

  # A credit from another instance's publication (docs/dev/SHARED-ACTIVITIES.md).
  def credit_remote? = credit? && remote_participation_id.present?

  # A positioned recording has geometry; a positionless one (docs/dev/NO-GPS.md)
  # was recorded without a fix and carries none. A credit row is never
  # positioned. The pair `start_point`/`bounds` exists or does not together.
  def positioned? = recording? && start_point.present?

  # The workout whose stored points derive this one's best efforts and
  # segment efforts: itself for a recording, the source for an attached credit
  # row, nil for a detached one, whose derived rows are frozen
  # (docs/dev/SHARED-ACTIVITIES.md).
  def track_workout = recording? ? self : credited_from

  # The figures this workout may show at all. A positionless recording carries
  # no elevation, and one whose file recorded no distance has no distance,
  # pace or speed to divide: those tiles would print zeros nobody measured
  # (docs/dev/NO-GPS.md).
  ELEVATION_METRIC_KEYS = %i[ascent descent min_elevation max_elevation].freeze
  DISTANCE_METRIC_KEYS = %i[
    distance average_speed max_speed average_pace best_pace grade_adjusted_pace
  ].freeze

  # A manual entry shows what its owner typed in and nothing an analysis
  # derives: no maximum speed, best pace, descent or elevation range.
  MANUAL_HIDDEN_METRIC_KEYS = %i[
    descent min_elevation max_elevation max_speed best_pace grade_adjusted_pace
    average_cadence max_cadence max_power points_count
  ].freeze
  MANUAL_OPTIONAL_METRIC_KEYS = %i[average_heart_rate max_heart_rate calories average_power].freeze

  def metric_visible?(key)
    key = key.to_sym
    return manual_metric_visible?(key) if manual?
    return grade_adjusted_pace.present? if key == :grade_adjusted_pace
    return false if positionless? && ELEVATION_METRIC_KEYS.include?(key)

    !(positionless? && !distance_recorded? && DISTANCE_METRIC_KEYS.include?(key))
  end

  # A recording imported without any position (docs/dev/NO-GPS.md).
  def positionless? = recording? && !positioned?

  # Whether the file's distance is worth showing: a duration-only session
  # persisted 0 because none was recorded.
  def distance_recorded? = distance.to_f.positive?

  def metrics_present? = true

  # Readings flagged by the analyzer (docs/dev/WORKOUT.md). Owner-only derived
  # data: never part of a publication snapshot or federation.
  def anomaly_findings = Array(data_anomalies&.fetch("findings", nil))

  private

  def manual_metric_visible?(key)
    return false if MANUAL_HIDDEN_METRIC_KEYS.include?(key)
    return ascent.to_f.positive? if key == :ascent
    return distance_recorded? if DISTANCE_METRIC_KEYS.include?(key)
    return public_send(key).present? if MANUAL_OPTIONAL_METRIC_KEYS.include?(key)

    true
  end

  def manual_figures_are_plausible
    MANUAL_LIMITS.each do |attribute, range|
      value = public_send(attribute)
      next if value.nil? || (attribute == :moving_time && errors.include?(:duration))

      errors.add(attribute, :implausible) unless range.cover?(value.to_f)
    end
    if average_heart_rate && max_heart_rate && max_heart_rate < average_heart_rate
      errors.add(:max_heart_rate, :below_average)
    end
    errors.add(:started_at, :in_future) if started_at && started_at > Time.current + 5.minutes
    errors.add(:ascent, :not_for_sport) if sport && ascent.to_f.positive? && !sport.records_elevation
  end

  def duration_components_are_consistent
    return unless duration && moving_time && pause_time

    errors.add(:moving_time, :less_than_or_equal_to, count: duration) if moving_time > duration
    errors.add(:pause_time, :invalid) unless pause_time == duration - moving_time
  end

  # A nil `bounds` is valid only for a recording without a start point, which
  # `geometry_columns_are_consistent` checks; a present one always has its
  # four values.
  def bounds_have_four_values
    errors.add(:bounds, :invalid) if bounds.present? && bounds.length != 4
  end

  def geometry_columns_are_consistent
    return if start_point.present? == bounds.present?

    errors.add(:start_point, :invalid)
    errors.add(:bounds, :invalid)
  end

  # Derived from the stored toponymy by Workouts::PlaceNamer; never part of a
  # publication snapshot.
  def places_are_an_array
    errors.add(:places, :invalid) unless places.is_a?(Array)
  end

  def recompute_records_on_create
    Records::RecomputeService.new(user:, sport:).call
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: id })
  end

  def recompute_records_on_update
    sports = [ sport ]
    if saved_change_to_sport_id?
      old_sport = Sport.find_by(id: sport_id_before_last_save)
      sports << old_sport if old_sport
    end
    sports.compact.uniq.each do |recompute_sport|
      Records::RecomputeService.new(user:, sport: recompute_sport).call
    end
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: id })
  end

  def recompute_records_on_destroy
    Records::RecomputeService.new(user:, sport:).call
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: id })
  end

  def records_relevant_change?
    return true if saved_change_to_sport_id?

    RECORD_SOURCE_COLUMNS.any? { |column| saved_change_to_attribute?(column) }
  end

  def capture_effort_segment_ids
    @effort_segment_ids = segment_efforts.distinct.pluck(:segment_id)
  end

  def credit_sync_relevant?
    recording? && saved_changes.keys.intersect?(Participations::CreditSync::SYNCED_COLUMNS)
  end

  def sync_credit_rows
    Participations::CreditSyncJob.nudge(self)
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: id })
  end

  # The owner's title leaves with the source; the figures and the participant's
  # records stay on their own row. Every participation of this workout, as
  # source or as linked recording, loses its open notices; the rows cascade.
  def detach_credit_rows
    now = Time.current
    @detached_credit_ids = credit_rows.pluck(:id)
    credit_rows.update_all(credited_from_workout_id: nil, credit_detached_at: now, title: nil, updated_at: now)
    (workout_participations.live.to_a + participant_links.live.to_a).each do |participation|
      Notifications::Withdraw.new(subject: participation).call!
    end
  end

  def enqueue_remote_withdrawal
    Comments::Outbound.enqueue!(@remote_withdrawal_event) if @remote_withdrawal_event
  end

  def notify_detached_credits
    return if @detached_credit_ids.blank?

    Workout.where(id: @detached_credit_ids).includes(:user).find_each do |credit|
      Notifications::Create.new(user: credit.user, kind: "participation_source_deleted", subject: credit).call!
    end
  end

  def withdraw_reaction_digest
    Notifications::Withdraw.new(kind: Notifications::ReactionDigest::KIND, subject: self).call!
  end

  def withdraw_credit_participation
    Notifications::Withdraw.new(subject: self).call!
    actor = user.actor
    # A remote credit taken out by its account: the invitation ends and the
    # owner hears of it, unless the account itself is being deleted — its
    # tombstoned actor mints nothing, and its Delete tells the owner instead.
    if remote_participation&.active?
      @remote_withdrawal_event = Participations::RemoteWithdrawal.withdraw!(
        remote_participation, notify_origin: actor.present? && !actor.tombstoned?, destroy_credit: false
      )
      return
    end
    return unless credited_from_workout_id && actor

    WorkoutParticipation.live.credits
      .where(workout_id: credited_from_workout_id, participant_actor: actor)
      .find_each do |participation|
        participation.update!(withdrawn_at: Time.current)
        Notifications::Withdraw.new(subject: participation).call!
      end
  end

  def refresh_effort_segments
    return if @effort_segment_ids.blank?

    Segments::RefreshJob.perform_later(@effort_segment_ids)
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: id })
  end

  def decrement_equipment_totals
    equipments.find_each do |equipment|
      Equipments::Totals.decrement(equipment, self)
    end
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: id })
  end

  def diff_equipment_totals
    old_distance, new_distance = saved_change_to_distance || [ distance, distance ]
    old_moving, new_moving = saved_change_to_moving_time || [ moving_time, moving_time ]
    equipments.find_each do |equipment|
      Equipments::Totals.diff(equipment, old_distance:, old_moving:, new_distance:, new_moving:)
    end
  rescue StandardError => error
    Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: id })
  end
end
