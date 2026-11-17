# frozen_string_literal: true

class User < ApplicationRecord
  LOCALES = %w[fr en de es nl].freeze
  THEMES = %w[light dark].freeze
  # Which generated route-image variant the browser shows. `auto` follows the
  # page theme (`current_theme`, DESIGN.md §15.4), like every map and chart;
  # `light` and `dark` force the variant regardless of the theme. The iOS
  # companion's own appearance reaches `current_theme` as a cookie, so `auto`
  # is right there too.
  ROUTE_IMAGE_THEMES = %w[auto light dark].freeze
  UNIT_SYSTEMS = %w[metric imperial].freeze
  WEEK_STARTS = %w[monday sunday].freeze
  # Track-display smoothing intensities (PLAN_MAPLIBRE.md §9). The window is a
  # display transform only: it never changes a payload, snapshot, or metric.
  TRACK_SMOOTHING_LEVELS = %w[light medium strong].freeze
  # The self-declared leaderboard category (PLAN_SEGMENTS.md §8.7). It only
  # offers a filtered view of a board; `unspecified` keeps the general board.
  LEADERBOARD_CATEGORIES = %w[unspecified women men].freeze
  # Local profile sections only, never publication or federation audiences.
  PROFILE_SHARING_AUDIENCES = %w[none followers members].freeze
  # Whether the account may be found by name search and suggestions
  # (docs/dev/PEOPLE.md). `none` is the default for everyone: the directory is
  # opt-in, and an exact handle still reaches a hidden account.
  DISCOVERABILITY = %w[none members].freeze
  TIME_ZONE_IDENTIFIERS = TZInfo::Timezone.all_identifiers.freeze
  # Who asked for a scheduled deletion (docs/dev/ACCOUNT.md).
  DELETION_REQUESTERS = %w[self operator].freeze

  # Generic sports an import detects when the file carries no usable sub-type
  # (PLAN_M1.md §3.4). An account may replace each of them with a variant of
  # the same icon family; the columns stay nil to keep the detected generic.
  SPORT_DEFAULT_KEYS = Sport::GENERIC_SLUGS.index_with { |slug| :"default_#{slug}_sport" }.freeze

  # Mirrors the users_username_format check constraint.
  USERNAME_FORMAT = /\A[a-z0-9_]{1,30}\z/

  # NIST SP 800-63B: single-factor memorized secrets are at least 15 characters
  # long, with no composition rules. BCrypt hashes at most 72 bytes.
  MINIMUM_PASSWORD_LENGTH = 15

  # Reserved because they collide with our own routes, with well-known
  # ActivityPub endpoints, with the instance's own identity, or with names
  # remote software treats specially. Handing one of these out would make the
  # instance's own endpoints unreachable — and it cannot be undone once the
  # actor has federated. The application surfaces stay in step with the router
  # through `spec/config/reserved_usernames_spec.rb`; the configured instance
  # name is refused separately, to self-registration alone
  # (`username_not_instance_name`).
  RESERVED_USERNAMES = %w[
    admin administrator root system support help
    moderator moderators staff team
    api inbox outbox followers following actor users user
    webfinger nodeinfo well_known oauth federation federation_follow
    allure allure_app allureapp allure_official allure_team allure_support
    allurerocks allures
    everyone here all me public group groups friends official
    www mail noreply no_reply postmaster hostmaster webmaster abuse security
    info contact billing press jobs status docs blog staging demo test dev
    media static cdn localhost
    feed people notifications settings segments route_suggestions records stats workouts
    equipments equipment imports workout_imports publications comments
    remote_notes remote_segments remote_participations developers mcp metrics
    cable auth session passwords registration onboarding invitations release_notes
    privacy_zones publishing_profiles account appearance units elevation
    connections sports data feedback styleguide manifest push funding
  ].freeze

  # Generated-avatar palette (DESIGN.md §9.2). A fixed curated pink set — never
  # raw HSL arithmetic — chosen so white meets 4.5:1 on every entry in both
  # themes. Contrast is a property of the palette.
  AVATAR_PALETTE = Allure::Avatar::Palette::COLOURS

  # An account created through an identity provider has no password
  # (docs/dev/AUTH.md), so Rails' built-in presence rule is replaced by the
  # explicit validations below.
  has_secure_password validations: false
  # Set by the provider sign-up, the only path that creates an account
  # without a password.
  attr_accessor :provider_signup
  # Virtual field for the settings password-change form; never persisted.
  attr_accessor :current_password
  # Virtual checkbox on the profile form: purge the uploaded avatar.
  attr_accessor :remove_avatar
  has_one_attached :avatar
  has_one_attached :gravatar_cache
  has_many :sessions, dependent: :destroy
  # Each goes with its session (docs/dev/PUSH.md), through the cascade.
  has_many :push_subscriptions, dependent: :delete_all
  # Second factors (docs/dev/AUTH.md).
  encrypts :otp_secret
  has_many :webauthn_credentials, dependent: :delete_all
  has_many :recovery_codes, dependent: :delete_all
  has_many :identities, dependent: :delete_all
  has_many :api_tokens, dependent: :delete_all
  has_many :webhook_endpoints, dependent: :destroy
  has_many :webhook_events, dependent: :delete_all
  has_many :workouts, dependent: :destroy
  has_many :workout_photos, dependent: :destroy
  validates :photo_quota_bytes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  has_many :workout_import_batches, dependent: :destroy
  has_many :import_connections, dependent: :destroy
  has_many :workout_bulk_operations, dependent: :destroy
  has_many :segments, dependent: :destroy
  has_many :segment_efforts, dependent: :destroy
  has_many :segment_opt_outs, dependent: :destroy, inverse_of: :user
  has_many :records, dependent: :destroy
  has_many :best_efforts, dependent: :destroy
  has_many :effort_records, dependent: :destroy
  has_many :equipments, dependent: :destroy
  has_many :publishing_profiles, dependent: :destroy, inverse_of: :user
  has_many :privacy_zones, dependent: :destroy, inverse_of: :user
  has_many :notifications, dependent: :destroy
  has_many :people_suggestion_dismissals, dependent: :delete_all
  # Recurring-route suggestions (PLAN_SEGMENTS.md §7.7): owner-only bookkeeping,
  # never a course and never published.
  has_many :route_suggestions, dependent: :destroy
  has_many :account_exports, dependent: :destroy
  has_many :funding_contributions, dependent: :destroy
  has_many :funding_subscriptions, dependent: :destroy
  has_many :active_funding_contributions, -> { current }, class_name: "FundingContribution"
  has_many :workout_publications, through: :workouts
  has_one :actor, inverse_of: :user
  belongs_to :default_cycling_sport, class_name: "Sport", optional: true
  belongs_to :default_running_sport, class_name: "Sport", optional: true
  belongs_to :default_walking_sport, class_name: "Sport", optional: true

  before_destroy :tombstone_actor
  # A brand-new account has missed nothing: mark the running release as seen so
  # the what's-new dialog only ever announces a release the account predates.
  before_create :mark_release_notes_seen
  before_create :assign_avatar_seed
  # A password account owes a second factor from the moment it holds a
  # password — at creation or when a password-less account adds one; the
  # grace period counts from here (docs/dev/AUTH.md).
  before_save :start_second_factor_requirement

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :username, with: ->(u) { u.to_s.strip.downcase }

  validates :username,
            presence: true,
            format: { with: USERNAME_FORMAT },
            uniqueness: { case_sensitive: false }
  # Reserved names are only checked while the name can still be chosen: the
  # username is immutable, and an account that holds a name a later release
  # reserves must keep saving its other attributes.
  validates :username,
            exclusion: { in: RESERVED_USERNAMES, message: :reserved },
            if: :new_record?

  validates :email_address,
            presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: true

  validates :password,
            length: { minimum: MINIMUM_PASSWORD_LENGTH },
            allow_nil: true
  validates :password, presence: true, on: :create, unless: :provider_signup
  validates :password, confirmation: true, allow_blank: true
  validate :password_within_bcrypt_limit

  validates :locale, inclusion: { in: LOCALES }
  validates :theme, inclusion: { in: THEMES }
  validates :route_image_theme, inclusion: { in: ROUTE_IMAGE_THEMES }
  validates :unit_system, inclusion: { in: UNIT_SYSTEMS }
  validates :week_start, inclusion: { in: WEEK_STARTS }
  validates :track_smoothing_level, inclusion: { in: TRACK_SMOOTHING_LEVELS }
  validates :leaderboard_category, inclusion: { in: LEADERBOARD_CATEGORIES }
  validates :smooth_tracks, inclusion: { in: [ true, false ] }
  validates :gravatar_opt_in, inclusion: { in: [ true, false ] }
  validates :profile_statistics_audience, :profile_records_audience, inclusion: { in: PROFILE_SHARING_AUDIENCES }
  validates :discoverable, inclusion: { in: DISCOVERABILITY }
  validates :elevation_enrichment_enabled, inclusion: { in: [ true, false ] }
  validates :weather_enrichment_enabled, inclusion: { in: [ true, false ] }
  validates :funding_badge_hidden, inclusion: { in: [ true, false ] }
  validates :funding_badge_color, inclusion: { in: Allure::Funding::BADGE_COLORS }
  validates :notify_follow_requests, inclusion: { in: [ true, false ] }
  validates :notify_follow_accepted, inclusion: { in: [ true, false ] }
  validates :notify_publication_activated, inclusion: { in: [ true, false ] }
  validates :notify_auto_published, inclusion: { in: [ true, false ] }
  validates :notify_auto_publication_failed, inclusion: { in: [ true, false ] }
  validates :notify_reactions, inclusion: { in: [ true, false ] }
  validates :notify_participation_requests, inclusion: { in: [ true, false ] }
  validates :notify_participation_confirmed, inclusion: { in: [ true, false ] }
  validates :display_name, length: { maximum: 60 }, allow_blank: true
  validates :bio, length: { maximum: 1000 }, allow_blank: true
  validates :time_zone, inclusion: { in: TIME_ZONE_IDENTIFIERS }
  validates :deletion_requested_by, inclusion: { in: DELETION_REQUESTERS }, allow_nil: true
  validate :username_immutable, if: :persisted?
  validate :username_not_retired, if: :new_record?
  validate :username_not_operator, on: :self_registration
  validate :username_not_instance_name, on: :self_registration
  validate :default_sports_are_allowed
  # The heart-rate profile (docs/dev/HEART-RATE.md).
  validates :max_heart_rate, numericality: { only_integer: true, in: 100..220 }, allow_nil: true
  validates :resting_heart_rate, numericality: { only_integer: true, in: 25..120 }, allow_nil: true
  validates :heart_rate_zone_basis, inclusion: { in: Allure::HeartRate::Zones::BASES }
  validate :heart_rate_profile_is_consistent

  after_commit :refresh_gravatar_cache, on: :update, if: :saved_change_to_gravatar_opt_in?

  # Accounts whose deletion window has ended, including a purge that stopped
  # half-way and must resume (docs/dev/ACCOUNT.md).
  scope :deletion_due, ->(now = Time.current) { where(deletion_scheduled_at: ..now) }
  # The accounts name search and suggestions may return (docs/dev/PEOPLE.md).
  # A deactivated account is never discoverable, whatever its setting says.
  scope :discoverable, -> { where(discoverable: "members", suspended_at: nil, deletion_scheduled_at: nil) }

  def display_name = self[:display_name].presence || username

  def password? = password_digest.present?

  def totp_enrolled? = otp_enrolled_at.present?

  def second_factor_enrolled? = totp_enrolled? || webauthn_credentials.exists?

  def second_factor_count = (totp_enrolled? ? 1 : 0) + webauthn_credentials.count

  # Operator suspension (docs/dev/ADMIN.md): access is revoked, content is not.
  def suspended? = suspended_at.present?

  # A scheduled deletion (docs/dev/ACCOUNT.md) deactivates the account for
  # its window: its content is hidden and nothing runs on its behalf.
  def deletion_scheduled? = deletion_scheduled_at.present?

  # Once the purge has started, the deletion can no longer be cancelled.
  def deletion_started? = deletion_started_at.present?

  # Nothing runs on behalf of a deactivated account: no notification, push,
  # webhook, synchronisation or automatic publication.
  def deactivated? = suspended? || deletion_scheduled?

  # Found by name search and suggestions (docs/dev/PEOPLE.md). The setting alone
  # is not enough: a deactivated account never appears.
  def discoverable? = discoverable == "members" && !deactivated?

  # The highest live tier owns the badge. The association can be preloaded on
  # avatar-heavy pages; no contribution state is copied onto the account.
  def funding_badge_tier
    active_funding_contributions.select(&:current?)
      .max_by { |contribution| FundingContribution::TIER_RANK.fetch(contribution.tier) }&.tier
  end

  def funding_badge_visible?
    Allure::Funding.enabled? && !deactivated? && !funding_badge_hidden? && funding_badge_tier.present?
  end

  # The one operator account (docs/dev/FEDERATION.md). Unset means nobody is an
  # operator; the console remains the fallback for administration.
  def instance_operator?
    configured = self.class.operator_username
    configured.present? && username == configured
  end

  def self.operator_username = ENV.fetch("INSTANCE_OPERATOR_USERNAME", "").strip.downcase

  # Generated-avatar seed (DESIGN.md §9.2): drawn once at account creation and
  # persisted, so the art is random across accounts but stable for each. The
  # fallback covers unsaved rows (styleguide, factories) without a seed.
  def avatar_seed = self[:avatar_seed] || Zlib.crc32(username.to_s)

  # The owner's preferred variant for a generic detected sport, or nil to keep
  # the detected sport. Only the generic slugs can be mapped.
  def preferred_sport_for(slug)
    attribute = SPORT_DEFAULT_KEYS[slug.to_s]
    return unless attribute

    sport = public_send(attribute)
    sport if sport&.active?
  end

  def heart_rate_profile? = max_heart_rate.present?

  # The account's five zones, or nil without a usable profile.
  def heart_rate_zones
    return nil unless heart_rate_profile?
    return nil if heart_rate_zone_basis == "reserve" && resting_heart_rate.blank?

    Allure::HeartRate::Zones.new(max: max_heart_rate, rest: resting_heart_rate,
                                 basis: heart_rate_zone_basis, bounds: heart_rate_zone_bounds)
  rescue ArgumentError, TypeError
    nil
  end

  # Server-resolved avatar chain (§9.1): uploaded image, then proxied Gravatar
  # when opted in and cached, then the generated art. The browser only ever
  # talks to this instance; a fetch failure is invisible (fall-through, never a
  # broken image).
  def gravatar_cached? = gravatar_opt_in? && gravatar_cache.attached?

  def avatar_image? = avatar.attached? || gravatar_cached?

  def avatar_source = avatar.attached? ? avatar : (gravatar_cached? ? gravatar_cache : nil)

  def refresh_gravatar_cache
    if gravatar_opt_in?
      Users::FetchGravatarCacheJob.perform_later(id)
    else
      gravatar_cache.purge_later
    end
  end

  # The operator role is a username comparison, so on an open instance whose
  # operator account does not exist yet the first visitor to register that
  # name would own /admin. The registration form (open or by invitation) never
  # hands it out; console creation (users:create) stays free.
  def username_not_operator
    configured = self.class.operator_username
    errors.add(:username, :reserved) if configured.present? && username == configured
  end

  # The instance's own name (`INSTANCE_NAME`) is refused for the same reason,
  # in its username-space form: a member could otherwise speak as the
  # instance. Console creation stays free for an official account.
  def username_not_instance_name
    return if username.blank?

    errors.add(:username, :reserved) if Allure::Instance.reserved_usernames.include?(username)
  end

  def username_immutable
    return unless will_save_change_to_username?

    errors.add(:username, :immutable)
  end

  # A deleted account's actor keeps its URI forever, and the URI derives from
  # the username: handing the name out again would leave the new account
  # unable to federate (docs/dev/ACCOUNT.md). Only the tombstoned actor of a
  # deleted account reserves the name — a live owner is the uniqueness rule's.
  def username_not_retired
    return if username.blank? || !username.match?(USERNAME_FORMAT)

    errors.add(:username, :retired) if Actor.where(local: true, uri: actor_uri, user_id: nil).exists?
  end

  def tombstone_actor
    actor&.tombstone!
  end

  def mark_release_notes_seen
    self.release_notes_seen_version ||= Allure::VERSION
  end

  def start_second_factor_requirement
    self.second_factor_required_since ||= Time.current if password_digest.present?
  end

  def password_within_bcrypt_limit
    return if password.nil? || password.bytesize <= ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED

    errors.add(:password, :password_too_long)
  end

  def assign_avatar_seed
    self.avatar_seed = SecureRandom.random_number(2**31) if self[:avatar_seed].nil?
  end

  # --- Federated identity -----------------------------------------------------
  # Derived, never stored. Storing them would let the row drift out of sync with
  # FEDERATION_BASE_URL and silently emit actor URIs the instance cannot serve.

  def actor_uri = federation_config.actor_uri(username)
  def handle = federation_config.handle(username)
  def key_id = federation_config.key_id(username)
  def profile_url = federation_config.profile_url(username)

  private

  # A default must be an active sport from the generic's curated target list
  # (PLAN_M1.md §3.4.2), which includes the generic itself; nil means the same
  # as choosing it.
  def default_sports_are_allowed
    SPORT_DEFAULT_KEYS.each do |generic_slug, attribute|
      sport = public_send(attribute)
      next if sport.nil?

      allowed = sport.active? &&
        Sport::DEFAULT_TARGET_SLUGS.fetch(generic_slug, []).include?(sport.slug)
      errors.add(:"#{attribute}_id", :invalid) unless allowed
    end
  end

  def heart_rate_profile_is_consistent
    bounds = Array(heart_rate_zone_bounds)
    unless bounds.size == Allure::HeartRate::Zones::COUNT - 1 &&
           bounds.all? { it.is_a?(Integer) && Allure::HeartRate::Zones::BOUND_RANGE.cover?(it) } &&
           bounds.each_cons(2).all? { |lower, upper| lower < upper }
      errors.add(:heart_rate_zone_bounds, :invalid_bounds)
    else
      zones = heart_rate_zones
      errors.add(:heart_rate_zone_bounds, :indistinct) if zones && !zones.distinct?
    end
    if resting_heart_rate && max_heart_rate && resting_heart_rate >= max_heart_rate
      errors.add(:resting_heart_rate, :not_below_maximum)
    end
    if heart_rate_zone_basis == "reserve" && max_heart_rate && resting_heart_rate.blank?
      errors.add(:resting_heart_rate, :required_for_reserve)
    end
  end

  def federation_config = Allure::Federation.config
end
