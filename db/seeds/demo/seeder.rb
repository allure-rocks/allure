# frozen_string_literal: true

require "digest"
require_relative "dating"

# The development demo dataset loader (db/seeds/development.rb). It drives a
# manifest (db/seeds/demo/manifests/*.rb) through the same services the web UI
# uses — the importer, the publishers, follows, comments, reactions,
# participations — so the demo state is exactly what a member could have
# produced. Every step finds before it creates, so a re-run writes nothing it
# already did; a failing entry is reported and never stops the run.
module DemoSeed
  PASSWORD = "allure-dev-password"
  # A fixed, public development secret (docs/dev/AUTH.md): every demo account
  # signs in with a second factor, as the operator must. Any authenticator app
  # or `ROTP::TOTP.new(TOTP_SECRET).now` gives the current code.
  TOTP_SECRET = "ALLUREDEVTOTPSECRETDEMOACCOUNTS2"
  # A fixed API token secret for REST/MCP experiments against the demo
  # instance. Only its SHA-256 digest is stored, like any other token.
  API_TOKEN_SECRET = "allure_pat_dev-demo-token-0000000000000000000000000000"

  class Runner
    Summary = Struct.new(:imported, :skipped, :failed, keyword_init: true)
    # A masked endpoint must be covered by an active zone, so every seeded
    # profile starts with both masks off: zones still remove the interior
    # points they cover, and an account whose activities all leave from home
    # turns a mask back on in its manifest entry.
    DEFAULT_MASKS = { "mask_start" => false, "mask_finish" => false }.freeze

    def initialize(manifest:, corpus_root:, fixtures_root:, out: $stdout, limit: nil,
                   file_time_shift: nil, manual_time_shift: nil, enrol_second_factor: true,
                   password_for: nil)
      @manifest = manifest
      @corpus_root = Pathname(corpus_root)
      @fixtures_root = Pathname(fixtures_root)
      @out = out
      @limit = limit
      # The seed dates its recordings near the present (docs/dev/DEMO.md,
      # DemoSeed::Dating): the two offsets in seconds are applied to file
      # imports (and their batches) and to typed manual entries respectively —
      # the manifest declares a separate anchor per family.
      @file_time_shift = file_time_shift
      @manual_time_shift = manual_time_shift
      # The demo's shared accounts sign in with a password alone; a demo run
      # passes false so no account holds a second factor at all.
      @enrol_second_factor = enrol_second_factor
      # A callable receiving the username and answering that account's
      # password (docs/dev/DEMO.md): the demo publishes one shared password and
      # hands every other account a fresh random one, so nobody can sign in as
      # a background persona from the repository's public development
      # constant. When nil, every account keeps DemoSeed::PASSWORD and an
      # existing password is never overwritten (the development behaviour).
      @password_for = password_for
      @users = {}
      @workouts = Hash.new { |hash, key| hash[key] = {} }
      @segments = Hash.new { |hash, key| hash[key] = {} }
      @comments = {}
      @summary = Summary.new(imported: 0, skipped: 0, failed: 0)
      @failures = []
    end

    def call
      @manifest.fetch(:accounts).each { |attributes| seed_account(attributes) }
      @manifest.fetch(:accounts).each { |attributes| seed_account_content(attributes) }
      @manifest.fetch(:follows, []).each { |entry| attempt("follow #{entry[:from]} -> #{entry[:to]}") { seed_follow(entry) } }
      @manifest.fetch(:accounts).each { |attributes| seed_publications(attributes) }
      @manifest.fetch(:participations, []).each { |entry| attempt("participation #{entry[:owner]}/#{entry[:workout]}") { seed_participation(entry) } }
      @manifest.fetch(:comments, []).each { |entry| attempt("comment #{entry[:key] || entry[:author]}") { seed_comment(entry) } }
      @manifest.fetch(:closed_threads, []).each { |entry| attempt("close #{entry[:owner]}/#{entry[:workout]}") { seed_closed_thread(entry) } }
      @manifest.fetch(:reactions, []).each { |entry| attempt("reaction #{entry[:by]} on #{entry[:workout]}") { seed_reaction(entry) } }
      @manifest.fetch(:opt_outs, []).each { |entry| attempt("opt-out #{entry[:user]}") { seed_opt_out(entry) } }
      @manifest.fetch(:copies, []).each { |entry| attempt("copy #{entry[:user]}/#{entry[:segment]}") { seed_copy(entry) } }
      @manifest.fetch(:api, []).each { |entry| attempt("api #{entry[:user]}") { seed_api(entry) } }
      seed_admin(@manifest.fetch(:admin, {}))
      report
      @summary
    end

    private

    # --- accounts ------------------------------------------------------------

    def seed_account(attributes)
      user = User.find_or_initialize_by(email_address: attributes.fetch(:email))
      user.assign_attributes(
        username: attributes.fetch(:username),
        display_name: attributes[:display_name],
        bio: attributes[:bio],
        locale: attributes.fetch(:locale, "fr"),
        theme: attributes.fetch(:theme, "light"),
        unit_system: attributes.fetch(:unit_system, "metric"),
        time_zone: attributes.fetch(:time_zone, "Europe/Paris"),
        week_start: attributes.fetch(:week_start, "monday"),
        leaderboard_category: attributes.fetch(:leaderboard_category, "unspecified"),
        route_image_theme: attributes.fetch(:route_image_theme, "auto"),
        smooth_tracks: attributes.fetch(:smooth_tracks, true),
        track_smoothing_level: attributes.fetch(:track_smoothing_level, "medium"),
        # Historical weather is opt-in per account (docs/dev/WEATHER.md); the
        # demo turns it on for the accounts a visitor browses.
        weather_enrichment_enabled: attributes.fetch(:weather_enrichment_enabled, false),
        # Optional profile sharing of totals and records (DESIGN.md §19.38):
        # the demo publishes them for the accounts a visitor reads.
        profile_statistics_audience: attributes.fetch(:profile_statistics_audience, "none"),
        profile_records_audience: attributes.fetch(:profile_records_audience, "none"),
        # Name search and suggestions are opt-in (docs/dev/PEOPLE.md); the demo
        # opts its personas in so the directory is not empty.
        discoverable: attributes.fetch(:discoverable, "none")
      )
      Sport::GENERIC_SLUGS.each do |generic|
        slug = attributes.dig(:default_sports, generic.to_sym)
        user.public_send(:"default_#{generic}_sport=", slug ? Sport.find_by!(slug:) : nil)
      end
      # A password_for proc always assigns: the demo re-points every account's
      # password on each pass, shared and background alike. Without it the
      # development password is only set once, never overwritten.
      if @password_for
        password = @password_for.call(attributes.fetch(:username))
        user.assign_attributes(password:, password_confirmation: password)
      elsif !user.password?
        user.assign_attributes(password: PASSWORD, password_confirmation: PASSWORD)
      end
      if @enrol_second_factor && attributes.fetch(:second_factor, true) && !user.totp_enrolled?
        user.assign_attributes(otp_secret: TOTP_SECRET, otp_enrolled_at: Time.current)
      end
      user.save!
      @users[attributes.fetch(:username)] = user
      say "account #{user.username} (#{user.email_address})"
      user
    end

    def seed_account_content(attributes)
      user = @users.fetch(attributes.fetch(:username))
      attributes.fetch(:equipment, []).each { |entry| attempt("equipment #{entry[:label]}") { seed_equipment(user, entry) } }
      attributes.fetch(:privacy_zones, []).each { |entry| attempt("zone #{entry[:name]}") { seed_privacy_zone(user, entry) } }
      attempt("profiles #{user.username}") { seed_profiles(user, attributes) }
      workouts = attributes.fetch(:workouts, [])
      workouts = workouts.first(@limit) if @limit
      workouts.each { |entry| attempt("workout #{entry[:key]}") { seed_workout(user, entry) } }
      attributes.fetch(:manual_workouts, []).each { |entry| attempt("manual workout #{entry[:key]}") { seed_manual_workout(user, entry) } }
      attributes.fetch(:batches, []).each { |entry| attempt("batch #{user.username}") { seed_batch(user, entry) } }
      attributes.fetch(:segments, []).each { |entry| attempt("segment #{entry[:name]}") { seed_segment(user, entry) } }
    end

    def seed_equipment(user, entry)
      user.equipments.find_or_create_by!(label: entry.fetch(:label)) do |equipment|
        equipment.equipment_type = EquipmentType.find_by!(slug: entry.fetch(:type))
        equipment.description = entry[:description]
      end
    end

    def seed_privacy_zone(user, entry)
      user.privacy_zones.find_or_create_by!(name: entry.fetch(:name)) do |zone|
        zone.latitude = entry.fetch(:latitude)
        zone.longitude = entry.fetch(:longitude)
        zone.radius_meters = entry.fetch(:radius_meters)
        zone.active = true
      end
    end

    # Built-in profiles exist for every account; the manifest may tune their
    # settings and policies and add custom public profiles. Attributes are
    # applied only when they differ, so a re-run writes nothing.
    def seed_profiles(user, attributes)
      I18n.with_locale(user.locale) { PublishingProfile.ensure_built_ins_for!(user) }
      PublishingProfile::AUDIENCES.each do |audience|
        profile = user.publishing_profiles.find_by!(built_in_key: audience)
        apply_profile_overrides(profile, attributes.dig(:built_in_profiles, audience.to_sym) || {})
      end
      attributes.fetch(:profiles, []).each_with_index do |entry, index|
        profile = user.publishing_profiles.find_or_create_by!(name: entry.fetch(:name)) do |created|
          created.audience = "public"
          created.position = PublishingProfile::AUDIENCES.length + index
          created.settings = PublishingProfile::DEFAULT_SETTINGS.deep_dup
        end
        apply_profile_overrides(profile, entry)
      end
    end

    def apply_profile_overrides(profile, overrides)
      desired = {}
      desired[:settings] = profile.settings.merge(DEFAULT_MASKS).merge(overrides.fetch(:settings, {}).deep_stringify_keys)
      desired[:publish_delay_seconds] = PublishingProfile::PUBLISH_DELAYS.fetch(overrides[:delay]) if overrides[:delay]
      if overrides.key?(:auto_publish)
        desired[:auto_publish] = overrides[:auto_publish]
        desired[:auto_publish_exclude_commute] = overrides.fetch(:auto_publish_exclude_commute, false)
      end
      changes = desired.reject { |attribute, value| profile.public_send(attribute) == value }
      return if changes.empty?

      profile.auto_publish_acknowledged = true if changes[:auto_publish]
      profile.update!(changes)
    end

    # --- workouts ------------------------------------------------------------

    def seed_workout(user, entry)
      path = resolve_source(entry)
      unless path
        @summary.skipped += 1
        say "skipping #{entry[:title]}: no source file (run script/fetch-fit-corpus)"
        return
      end

      digest = Digest::SHA256.file(path).hexdigest
      if (existing = user.workouts.find_by(source_digest: digest))
        @summary.skipped += 1
        register_workout(user, entry, existing)
        return
      end

      equipment_ids = Array(entry[:equipment]).map { |label| user.equipments.find_by!(label:).id }
      sport = entry[:sport] ? Sport.find_by!(slug: entry[:sport]) : nil
      result = File.open(path, "rb") do |io|
        Workouts::Importer.new(
          user:,
          uploaded_file: io,
          sport:,
          title: entry.fetch(:title),
          description: entry[:description],
          notes: entry[:notes],
          filename: File.basename(path),
          source_digest: digest,
          equipment_ids:,
          commute: entry[:commute] == true,
          time_shift: @file_time_shift
        ).call
      end

      if result.success?
        workout = result.workout
        # The file's own commute statement is a fact the owner may still
        # clear, exactly as the workout form does.
        workout.update_column(:commute, false) if entry[:commute] == false && workout.commute?
        register_workout(user, entry, workout)
        @summary.imported += 1
        say "imported #{user.username}: #{workout.title} (#{result.sport_source})"
      elsif result.duplicate?
        @summary.skipped += 1
      else
        failed("workout #{entry[:title]}", result.errors.to_sentence)
      end
    end

    # The figures a manual entry declares (docs/dev/MANUAL-ENTRY.md), in SI as
    # Workouts::ManualEntry takes them.
    MANUAL_FIGURES = %i[duration moving_time distance ascent average_heart_rate max_heart_rate calories average_power].freeze

    # A workout typed in by hand: no source file, so it is found again by its
    # title among the account's manual entries. `started_at` is local time in
    # the account's zone, as the form reads it.
    def seed_manual_workout(user, entry)
      if (existing = user.workouts.manual_entries.find_by(title: entry.fetch(:title)))
        register_workout(user, entry, existing)
        return
      end

      zone = Time.find_zone(user.time_zone) || Time.zone
      attributes = entry.slice(*MANUAL_FIGURES).merge(
        sport: Sport.find_by!(slug: entry.fetch(:sport)),
        started_at: zone.parse(entry.fetch(:started_at)) + @manual_time_shift.to_i,
        title: entry.fetch(:title),
        description: entry[:description],
        notes: entry[:notes],
        commute: entry[:commute] == true
      )
      equipment_ids = Array(entry[:equipment]).map { |label| user.equipments.find_by!(label:).id }
      result = Workouts::ManualEntry.create(user:, attributes:, equipment_ids:)
      return failed("manual workout #{entry[:title]}", result.workout.errors.full_messages.to_sentence) unless result.success?

      register_workout(user, entry, result.workout)
      say "entered #{user.username}: #{result.workout.title}"
    end

    def register_workout(user, entry, workout)
      @workouts[user.username][entry.fetch(:key)] = workout
    end

    # A corpus entry falls back to a committed fixture when the corpus has not
    # been fetched (the minimal manifest keeps one for each of its files).
    def resolve_source(entry)
      if entry[:file]
        path = @corpus_root.join(entry[:file])
        return path if path.file?
      end
      if entry[:fixture]
        path = @fixtures_root.join(entry[:fixture])
        return path if path.file?
      end
      nil
    end

    # One real batch run inline: the import history page and the operator's
    # failure list get a batch with a failed entry.
    def seed_batch(user, entry)
      files = entry.fetch(:files).filter_map do |file|
        path = resolve_source(file)
        path ? [ path, file ] : nil
      end
      if files.length < entry.fetch(:files).length
        say "skipping batch for #{user.username}: a source file is missing"
        return
      end

      keys_by_digest = files.to_h { |path, file| [ Digest::SHA256.file(path).hexdigest, file[:key] ] }.compact
      if user.workout_import_batches.where(source: "file").exists?
        user.workouts.where(source_digest: keys_by_digest.keys).find_each do |workout|
          @workouts[user.username][keys_by_digest.fetch(workout.source_digest)] = workout
        end
        return
      end

      batch = user.workout_import_batches.new(
        source: "file",
        trigger: "manual",
        sport: Sport.find_by!(slug: entry.fetch(:sport)),
        notes: entry[:notes]
      )
      # Active Storage uploads after the commit, so the handles stay open
      # until the transaction has completed.
      handles = files.map { |path, _file| File.open(path, "rb") }
      begin
        WorkoutImportBatch.transaction do
          batch.save!
          files.each_with_index do |(path, file), index|
            batch.source_files.attach(
              io: handles[index],
              filename: file[:as] || File.basename(path),
              content_type: "application/octet-stream"
            )
          end
        end
      ensure
        handles.each(&:close)
      end
      Workouts::ImportBatchJob.perform_now(batch, time_shift: @file_time_shift)
      batch.reload
      batch.entries.includes(:workout).find_each do |batch_entry|
        workout = batch_entry.workout
        next unless workout

        @summary.imported += 1
        key = keys_by_digest[workout.source_digest]
        @workouts[user.username][key] = workout if key
      end
      say "batch for #{user.username}: #{batch.imported_entries} imported, #{batch.failed_entries} failed"
    end

    # --- segments ------------------------------------------------------------

    # A route's whole-track default is wider than a segment's (PLAN_SEGMENTS.md
    # §4.8); the demo's routes follow the same form default as a member's.
    def default_tolerance_for(kind)
      if kind == "route"
        Segments::Creator::ROUTE_MATCH_TOLERANCE_METERS
      else
        Segments::Creator::DEFAULT_MATCH_TOLERANCE_METERS
      end
    end

    def seed_segment(user, entry)
      segment = user.segments.find_by(name: entry.fetch(:name))
      unless segment
        workout = find_workout(user.username, entry.fetch(:workout))
        return say("skipping segment #{entry[:name]}: workout #{entry[:workout]} is missing") unless workout

        start_index, end_index = anchor_indexes(workout, entry)
        sport = entry.key?(:sport) ? (entry[:sport] && Sport.find_by!(slug: entry[:sport])) : Segments::Creator::INHERIT_SPORT
        kind = entry.fetch(:kind, "segment")
        segment = Segments::Creator.new(
          user:,
          workout:,
          name: entry.fetch(:name),
          description: entry[:description],
          kind:,
          start_index:,
          end_index:,
          match_tolerance_meters: entry.fetch(:tolerance, default_tolerance_for(kind)),
          sport:,
          visibility: entry[:visibility],
          zone_acknowledged: entry.fetch(:zone_acknowledged, false)
        ).call
        unless segment.persisted?
          failed("segment #{entry[:name]}", segment.errors.full_messages.to_sentence)
          return
        end
        say "segment #{user.username}: #{segment.name} (#{segment.kind}, #{segment.visibility}, #{(segment.distance / 1000.0).round(1)} km)"
      end
      @segments[user.username][entry.fetch(:key)] = segment
      return unless entry[:publish] && segment.shareable? && segment.active_publication.nil?

      Segments::Publisher.new(user:, segment:).call!
      say "published course #{segment.name}"
    end

    # A segment is anchored by coordinates on its source workout: the nearest
    # recorded point to the start, then the nearest to the end within the same
    # recording segment, which is what the Creator requires. A route spans the
    # whole track and needs no anchors.
    def anchor_indexes(workout, entry)
      return [ nil, nil ] unless entry[:start] && entry[:end]

      points = Allure::Segments::PointStream.new(
        segments: workout.track_segments,
        workout_started_at: workout.started_at
      ).call
      start_index = nearest_point_index(points, entry.fetch(:start))
      candidates = points.select { |point| point.index > start_index && point.segment_index == points[start_index].segment_index }
      end_index = nearest_point_index(candidates, entry.fetch(:end))
      [ start_index, end_index ]
    end

    def nearest_point_index(points, coordinate)
      latitude, longitude = coordinate
      points.min_by { |point| Allure::Gpx::Geo.horizontal_distance(point.latitude, point.longitude, latitude, longitude) }&.index
    end

    # --- social --------------------------------------------------------------

    def seed_follow(entry)
      follower = @users.fetch(entry.fetch(:from))
      followed = @users.fetch(entry.fetch(:to))
      following = Federation::Follow.new(user: follower, target: followed.username).call!
      decision = entry.fetch(:decision, "accept")
      return following unless following.pending? && %w[accept reject].include?(decision)

      Federation::FollowDecision.new(following:, decision:).call!
    end

    def seed_publications(attributes)
      user = @users.fetch(attributes.fetch(:username))
      attributes.fetch(:workouts, []).each do |entry|
        publish_requests(entry[:publish]).each_with_index do |publish, index|
          attempt("publish #{entry[:key]}") { seed_publication(user, entry, publish, index) }
        end
      end
    end

    # `publish:` is an audience, a request hash (audience or profile name, an
    # optional delay preset), or a list of either.
    def publish_requests(publish)
      list = publish.is_a?(Array) ? publish : [ publish ].compact
      list.map { |request| request.is_a?(Hash) ? request : { audience: request } }
    end

    def seed_publication(user, entry, publish, index)
      workout = find_workout(user.username, entry.fetch(:key))
      return unless workout

      profile = if publish[:profile]
        user.publishing_profiles.find_by!(name: publish[:profile])
      else
        user.publishing_profiles.find_by!(built_in_key: publish.fetch(:audience).to_s)
      end
      workout.reset_publications
      return if workout.active_publication_for(profile.audience) || workout.scheduled_publication_for(profile.audience)

      delay = publish[:delay] ? PublishingProfile::PUBLISH_DELAYS.fetch(publish[:delay]) : profile.publish_delay_seconds
      now = Time.current
      published_at = [ publication_moment(user, entry, workout, index), now - LATEST_PUBLICATION_MARGIN ].min
      release = published_at + delay
      if release > now
        publication = Workouts::Publisher.new(user:, workout:, profile:, delay:).call!
        hold_until(publication, release)
      else
        publication = Workouts::Publisher.new(user:, workout:, profile:, delay: 0).call!
        backdate(publication, release)
      end
      say "published #{user.username}: #{workout.title} (#{profile.audience}#{publication.status == 'scheduled' ? ', scheduled' : ''})"
    end

    # A seeded publication is dated as its owner would have published it, a
    # little after finishing the workout, so the feed interleaves the accounts
    # in the order they went out instead of in the order the seed ran.
    LATEST_PUBLICATION_MARGIN = 60

    # Deterministic per workout, so every run and every reset lands on the
    # same moment; a second audience follows its first a few minutes later.
    def publication_moment(user, entry, workout, index)
      random = Random.new(Digest::SHA256.hexdigest("#{user.username}/#{entry.fetch(:key)}").to_i(16))
      roll = random.rand
      minutes = if roll < 0.7 then random.rand(10..90)
      elsif roll < 0.9 then random.rand(120..360)
      else random.rand(720..1200)
      end
      minutes += (1..index).sum { random.rand(2..12) }
      workout.started_at + workout.duration + (minutes * 60)
    end

    # The delay ends after the publication's own moment, not after the seed
    # run: the activation job is queued again for that instant, and the one
    # the publisher queued finds it active and does nothing. Both rewrites are
    # the seed's own exception to a publication's immutability, written
    # through the relation as WorkoutPublication#activate! does.
    def hold_until(publication, release)
      return unless publication.scheduled?

      WorkoutPublication.where(id: publication.id).update_all(scheduled_for: release, published_at: release)
      Workouts::ScheduledPublicationActivation.enqueue_job(publication.reload)
    end

    # A delay that already ran out: the publication went live at its end.
    def backdate(publication, at)
      WorkoutPublication.where(id: publication.id, status: "active").update_all(published_at: at)
      publication.reload
    end

    def seed_participation(entry)
      owner = @users.fetch(entry.fetch(:owner))
      participant = @users.fetch(entry.fetch(:participant))
      workout = find_workout(owner.username, entry.fetch(:workout))
      return unless workout

      # A declined or withdrawn pair is terminal: a previous run's answer stands.
      participant_actor = Federation::ActorProvisioner.new(user: participant).call!
      existing = workout.workout_participations.find_by(participant_actor:)
      return existing if existing && !existing.active?

      participation = Participations::Propose.new(user: owner, workout:, target: participant.username).call!
      decision = entry[:decision]
      return unless decision && participation.active? && participation.participant_confirmed_at.nil?

      participant_workout = entry[:with_workout] && find_workout(participant.username, entry[:with_workout])
      withdraw_detected_links(participant, participant_workout) if participant_workout && decision == "confirm"
      Participations::Decide.new(participation:, user: participant, decision:, participant_workout:).call!
    end

    # Together detection runs on the worker while the seed imports, and may
    # already have suggested the participant's recording to another partner
    # of the same outing: one recording links to one live participation. The
    # manifest's link is the participant's answer, so they withdraw that
    # unconfirmed suggestion first, as a member would before naming the
    # recording (a decline would still hold it).
    def withdraw_detected_links(participant, recording)
      WorkoutParticipation.live.where(participant_workout: recording, origin: "detection").find_each do |suggestion|
        next unless suggestion.active? && suggestion.participant_confirmed_at.nil?

        Participations::Withdraw.new(participation: suggestion, user: participant).call!
      end
    end

    def seed_comment(entry)
      author = @users.fetch(entry.fetch(:author))
      owner = @users.fetch(entry.fetch(:owner))
      workout = find_workout(owner.username, entry.fetch(:workout))
      return unless workout

      body = Comments::Post.normalize(entry.fetch(:body))
      actor = Federation::ActorProvisioner.new(user: author).call!
      # A deleted or removed comment loses its words, so a previous run's copy
      # is recognised by its state instead of its body.
      comment = Comment.find_by(actor:, workout:, body:)
      comment ||= Comment.find_by(actor:, workout:, status: entry[:state].to_s) if entry[:state]
      comment ||= Comments::Post.new(
        user: author, target: workout, body:, parent_id: entry[:parent] && @comments.fetch(entry[:parent]).to_param
      ).call!
      @comments[entry[:key]] = comment if entry[:key]
      case entry[:state]
      when :deleted then Comments::Delete.new(user: author, comment:).call! if comment.active?
      when :removed then Comments::Remove.new(user: owner, comment:).call! if comment.active?
      end
      comment
    end

    def seed_closed_thread(entry)
      owner = @users.fetch(entry.fetch(:owner))
      workout = find_workout(owner.username, entry.fetch(:workout))
      Comments::Close.new(user: owner, workout:, closed: true).call! if workout
    end

    def seed_reaction(entry)
      user = @users.fetch(entry.fetch(:by))
      workout = find_workout(entry.fetch(:owner), entry.fetch(:workout))
      return unless workout

      actor = Federation::ActorProvisioner.new(user:).call!
      return if Reaction.active.exists?(actor:, workout:)

      Reactions::Toggle.new(user:, target: workout, kind: entry.fetch(:kind)).call!
    end

    def seed_opt_out(entry)
      user = @users.fetch(entry.fetch(:user))
      segment = find_segment(entry.fetch(:owner), entry.fetch(:segment))
      SegmentOptOut.find_or_create_by!(segment:, user:) if segment
    end

    def seed_copy(entry)
      user = @users.fetch(entry.fetch(:user))
      segment = find_segment(entry.fetch(:owner), entry.fetch(:segment))
      return unless segment

      reversed = entry.fetch(:reversed, false)
      I18n.with_locale(user.locale) do
        name = reversed ? I18n.t("segments.copy.reversed_name", name: segment.name).first(120) : segment.name
        return if user.segments.exists?(name:)

        Segments::LocalCopier.new(user:, segment:, reversed:).call!
      end
    end

    # --- API -----------------------------------------------------------------

    def seed_api(entry)
      user = @users.fetch(entry.fetch(:user))
      entry.fetch(:tokens, []).each do |token|
        next if user.api_tokens.exists?(name: token.fetch(:name))

        if token[:revoked]
          created, _secret = ApiToken.issue!(user:, name: token.fetch(:name), scopes: token.fetch(:scopes), expires_in_days: 30)
          created.revoke!(by: "owner")
        else
          ApiToken.create!(
            user:,
            name: token.fetch(:name),
            scopes: token.fetch(:scopes),
            token_prefix: API_TOKEN_SECRET.first(ApiToken::DISPLAYED_PREFIX_LENGTH),
            token_digest: ApiToken.digest(API_TOKEN_SECRET),
            expires_at: 365.days.from_now,
            mcp_geometry: token.fetch(:mcp_geometry, "none")
          )
        end
      end
      entry.fetch(:webhooks, []).each do |webhook|
        next if user.webhook_endpoints.exists?(url: webhook.fetch(:url))

        user.webhook_endpoints.create!(
          url: webhook.fetch(:url),
          description: webhook[:description],
          events: webhook.fetch(:events, [ WebhookEndpoint::ALL_EVENTS ]),
          active: webhook.fetch(:active, false)
        )
      end
    end

    # --- administration ------------------------------------------------------

    def seed_admin(admin)
      operator = admin[:operator] && @users[admin[:operator]]
      admin.fetch(:invitations, []).each do |email|
        attempt("invitation #{email}") do
          next if RegistrationInvitation.exists?(email_address: email)

          invitation, _token = RegistrationInvitation.issue(email_address: email, expires_in: 14.days)
          Admin::Audit.record(actor: operator, action: :invitation_created, subject: invitation, metadata: { "email" => email })
        end
      end
      admin.fetch(:suspended, []).each do |entry|
        attempt("suspend #{entry[:username]}") do
          user = @users.fetch(entry.fetch(:username))
          next if user.suspended?

          user.update!(suspended_at: Time.current, suspension_reason: entry[:reason])
          user.sessions.destroy_all
          Admin::Audit.record(actor: operator, action: :account_suspended, subject: user, metadata: { "username" => user.username })
        end
      end
      admin.fetch(:identities, []).each do |entry|
        attempt("identity #{entry[:username]}") do
          user = @users.fetch(entry.fetch(:username))
          Identity.find_or_create_by!(issuer: entry.fetch(:issuer), subject: entry.fetch(:subject)) do |identity|
            identity.user = user
            identity.provider = entry.fetch(:provider)
            identity.email = user.email_address
            identity.email_verified = true
            identity.linked_at = Time.current
          end
        end
      end
    end

    # --- helpers -------------------------------------------------------------

    def find_workout(username, key)
      @workouts[username][key] || begin
        say "workout #{username}/#{key} is not available"
        nil
      end
    end

    def find_segment(username, key)
      @segments[username][key] || begin
        say "segment #{username}/#{key} is not available"
        nil
      end
    end

    def attempt(label)
      yield
    rescue StandardError => error
      failed(label, "#{error.class}: #{error.message}")
    end

    def failed(label, message)
      @summary.failed += 1
      @failures << "#{label}: #{message}"
      say "FAILED #{label}: #{message}"
    end

    def say(message)
      @out.puts("[seeds] #{message}")
    end

    def report
      say "demo dataset: #{@summary.imported} workouts imported, #{@summary.skipped} already present, #{@summary.failed} failures"
      @failures.each { |failure| say "  - #{failure}" }
    end
  end
end
