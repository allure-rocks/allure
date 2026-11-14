# frozen_string_literal: true

require "csv"

module Users
  # Writes the account's data archive (PLAN_ACCOUNT.md §3.3) into `path`: the
  # original files as imported, in nested ZIP archives the import page takes
  # back as they are, and everything else as JSON and CSV in SI units. Rows
  # are read in batches and written as they go, and each original is copied
  # one at a time, so no account is ever held in memory. No secret ever
  # enters the archive: no password, factor, token, webhook secret,
  # connection credential or private key.
  class ExportArchive
    VERSION = 1
    ORIGINALS_PER_ARCHIVE = Workouts::ArchiveReader::MAX_ARCHIVE_ENTRIES
    COUNTED = %w[workouts credited_workouts originals photos segments publications following followers comments reactions].freeze
    WORKOUT_CSV_COLUMNS = %w[
      id title sport started_at elapsed_time moving_time distance ascent descent
      average_speed max_speed average_heart_rate max_heart_rate average_cadence
      average_power calories commute origin device places equipment_ids original_file
    ].freeze

    def initialize(user:, now: Time.current)
      @user = user
      @now = now
      @counts = COUNTED.index_with(0)
    end

    # Answers the counts written, which the export row keeps.
    def write(path)
      Zip::OutputStream.open(path) do |zip|
        @zip = zip
        write_readme
        write_json("account.json", account)
        write_json("sessions.json", sessions)
        original_names = write_originals
        write_workouts(original_names)
        write_json("records.json", records)
        write_segments
        write_json("equipment.json", @user.equipments.includes(:equipment_type).order(:id).map { serializers::CatalogSerializers.equipment(it) })
        write_json("publishing_profiles.json", publishing_profiles)
        write_json("privacy_zones.geojson", privacy_zones)
        write_json("publications.json", publications)
        write_social
        write_avatar
        write_photos
      end
      @counts
    end

    private

    def serializers = Api::Rest::V1

    def time(value) = serializers::Formats.time(value)

    def actor = @user.actor

    def entry(name, compression: Zip::Entry::DEFLATED)
      @zip.put_next_entry(name, nil, nil, compression)
    end

    def write_json(name, value)
      entry(name)
      @zip.write(JSON.pretty_generate(value))
    end

    def write_readme
      { "LISEZMOI.txt" => :fr, "README.txt" => :en }.each do |name, locale|
        entry(name)
        @zip.write(I18n.t("account_exports.readme", locale:, username: @user.username,
                                                    date: I18n.l(@now.to_date, format: :long, locale:),
                                                    version: VERSION, per_archive: ORIGINALS_PER_ARCHIVE))
      end
    end

    def account
      {
        export_version: VERSION,
        exported_at: time(@now),
        username: @user.username,
        handle: @user.handle,
        display_name: @user[:display_name],
        bio: @user.bio,
        email_address: @user.email_address,
        created_at: time(@user.created_at),
        preferences: {
          locale: @user.locale,
          theme: @user.theme,
          unit_system: @user.unit_system,
          time_zone: @user.time_zone,
          week_start: @user.week_start,
          route_image_theme: @user.route_image_theme,
          smooth_tracks: @user.smooth_tracks,
          track_smoothing_level: @user.track_smoothing_level,
          gravatar_opt_in: @user.gravatar_opt_in,
          profile_statistics_audience: @user.profile_statistics_audience,
          profile_records_audience: @user.profile_records_audience,
          discoverable: @user.discoverable,
          elevation_enrichment_enabled: @user.elevation_enrichment_enabled,
          together_detection_enabled: @user.together_detection_enabled,
          leaderboard_category: @user.leaderboard_category,
          funding_badge_hidden: @user.funding_badge_hidden,
          funding_badge_color: @user.funding_badge_color,
          default_sports: User::SPORT_DEFAULT_KEYS.to_h { |slug, attribute| [ slug, @user.public_send(attribute)&.slug ] }
        },
        funding_contributions: @user.funding_contributions.order(:id).map do
          { provider: it.provider, tier: it.tier, paid_at: time(it.paid_at), starts_at: time(it.starts_at), expires_at: time(it.expires_at), status: it.status }
        end,
        funding_subscriptions: @user.funding_subscriptions.order(:id).map do
          { provider: it.provider, tier: it.tier, status: it.status, cancel_at_period_end: it.cancel_at_period_end,
            canceled_at: time(it.canceled_at), synced_at: time(it.synced_at), created_at: time(it.created_at) }
        end,
        heart_rate_profile: serializers::HeartRateSerializer.profile(@user),
        notifications: @user.attributes.select { |key, _| key.start_with?("notify_") },
        second_factors: {
          authenticator_app_enrolled_at: time(@user.otp_enrolled_at),
          passkeys: @user.webauthn_credentials.order(:id).map { { name: it.nickname, created_at: time(it.created_at), last_used_at: time(it.last_used_at) } },
          recovery_codes_remaining: @user.recovery_codes.where(used_at: nil).count
        },
        identity_providers: @user.identities.order(:id).map { { provider: it.provider, linked_at: time(it.linked_at), last_used_at: time(it.last_used_at) } },
        import_connections: @user.import_connections.order(:id).map do
          { provider: it.provider, status: it.status, linked_at: time(it.linked_at), last_synced_at: time(it.last_synced_at) }
        end
      }
    end

    def sessions
      @user.sessions.order(:created_at).map do
        {
          created_at: time(it.created_at),
          last_seen_at: time(it.last_seen_at),
          device: it.user_agent,
          ip_address: it.ip_address,
          sign_in_method: it.auth_method
        }
      end
    end

    # Originals go first, one nested archive per ORIGINALS_PER_ARCHIVE files,
    # each written to its own temporary file and stored as is: FIT files
    # barely compress and the nested archive is already deflated.
    def write_originals
      names = {}
      @user.workouts.recordings.order(:started_at, :id).includes(original_file_attachment: :blob)
        .each_slice(ORIGINALS_PER_ARCHIVE).with_index(1) do |workouts, index|
        Tempfile.create([ "allure-export-originals-", ".zip" ]) do |file|
          Zip::OutputStream.open(file.path) do |inner|
            workouts.each do |workout|
              next unless workout.original_file.attached?

              name = original_name(workout)
              inner.put_next_entry(name)
              workout.original_file.blob.open { |io| IO.copy_stream(io, inner) }
              names[workout.id] = format("workouts/originals-%03d.zip", index) + "!/#{name}"
              @counts["originals"] += 1
            end
          end
          entry(format("workouts/originals-%03d.zip", index), compression: Zip::Entry::STORED)
          File.open(file.path, "rb") { |io| IO.copy_stream(io, @zip) }
        end
      end
      names
    end

    def original_name(workout)
      extension = File.extname(workout.original_file.filename.to_s).downcase
      unless Allure::ImportFormat::EXTENSIONS.include?(extension)
        extension = Allure::ImportFormat.for_key(workout.import_format)&.extension || ".bin"
      end
      "#{workout.started_at.utc.strftime('%Y-%m-%d_%H%M')}_#{workout.to_param}#{extension}"
    end

    # The JSON index streams straight into its entry while the CSV index
    # waits in a temporary file: a ZIP stream writes one entry at a time.
    def write_workouts(original_names)
      Tempfile.create([ "allure-export-workouts-", ".csv" ]) do |csv|
        csv.write(Allure::CsvCell.line(WORKOUT_CSV_COLUMNS))
        entry("workouts/index.json")
        @zip.write("[")
        @user.workouts
          .includes(:sport, :equipments, :import_connection, :active_publications, :scheduled_publications, :credited_by,
                    :weather, :heart_rate)
          .find_each do |workout|
          body = serializers::WorkoutSerializer.new(workout, detail: true).as_json
          @zip.write(@counts["workouts"].zero? ? "\n" : ",\n")
          @zip.write(JSON.generate(body))
          csv.write(Allure::CsvCell.line(workout_row(body, original_names[workout.id])))
          @counts["workouts"] += 1
          @counts["credited_workouts"] += 1 if workout.credit?
        end
        @zip.write("\n]\n")
        csv.flush
        csv.rewind
        entry("workouts/index.csv")
        IO.copy_stream(csv, @zip)
      end
    end

    def workout_row(body, original)
      WORKOUT_CSV_COLUMNS.map do |column|
        case column
        when "places", "equipment_ids" then Array(body[column.to_sym]).join(" | ")
        when "original_file" then original
        else body[column.to_sym]
        end
      end
    end

    def records
      {
        records: @user.records.includes(:sport, :workout).order(:id).map do
          {
            record_type: it.record_type,
            sport: it.sport.slug,
            value: serializers::Formats.number(it.value),
            workout_id: it.workout&.to_param,
            workout_started_at: time(it.workout_started_at)
          }
        end,
        best_efforts: @user.best_efforts.includes(:sport, :workout).order(:id).map do
          {
            sport: it.sport.slug,
            distance_key: it.distance_key,
            distance: serializers::Formats.number(it.distance_meters),
            elapsed_time: it.duration_seconds,
            started_at: time(it.started_at),
            workout_id: it.workout&.to_param
          }
        end,
        effort_records: @user.effort_records.includes(:sport, :workout).order(:id).map do
          {
            sport: it.sport.slug,
            distance_key: it.distance_key,
            distance: serializers::Formats.number(it.distance_meters),
            elapsed_time: it.duration_seconds,
            workout_id: it.workout&.to_param,
            workout_started_at: time(it.workout_started_at)
          }
        end
      }
    end

    def write_segments
      segments = []
      features = []
      @user.segments.includes(:sport).find_each do |segment|
        properties = {
          id: segment.to_param,
          name: segment.name,
          kind: segment.kind,
          sport: segment.sport&.slug,
          visibility: segment.visibility,
          description: segment.description,
          distance: serializers::Formats.number(segment.distance),
          ascent: serializers::Formats.number(segment.ascent),
          descent: serializers::Formats.number(segment.descent),
          average_grade: serializers::Formats.number(segment.average_grade),
          place: segment.place_name,
          created_at: time(segment.created_at)
        }
        segments << properties.merge(elevation_profile: segment.elevation_profile)
        features << { type: "Feature", properties:, geometry: line_string(segment.geom) }
        @counts["segments"] += 1
      end
      write_json("segments.json", segments)
      write_json("segments.geojson", { type: "FeatureCollection", features: })
    end

    def line_string(geom)
      { type: "LineString", coordinates: geom.points.map { [ it.x, it.y ] } }
    end

    def publishing_profiles
      @user.publishing_profiles.order(:position, :id).map do
        serializers::CatalogSerializers.publishing_profile(it).merge(settings: it.settings)
      end
    end

    def privacy_zones
      features = @user.privacy_zones.order(:id).map do |zone|
        {
          type: "Feature",
          properties: { name: zone.name, radius: zone.radius_meters, active: zone.active, created_at: time(zone.created_at) },
          geometry: { type: "Point", coordinates: [ zone.center.x, zone.center.y ] }
        }
      end
      { type: "FeatureCollection", features: }
    end

    def publications
      return { workouts: [], segments: [] } unless actor

      {
        workouts: WorkoutPublication.where(actor:).includes(:workout).order(:published_at, :id).map do |publication|
          @counts["publications"] += 1
          {
            id: publication.to_param,
            workout_id: publication.workout&.to_param,
            audience: publication.audience,
            status: publication.status,
            published_at: time(publication.published_at),
            scheduled_for: time(publication.scheduled_for),
            deleted_at: time(publication.deleted_at),
            object_uri: publication.object_uri,
            profile: publication.profile_snapshot,
            representation: publication.representation
          }
        end,
        segments: SegmentPublication.where(actor:).includes(:segment).order(:published_at, :id).map do |publication|
          {
            id: publication.to_param,
            segment_id: publication.segment&.to_param,
            audience: publication.audience,
            status: publication.status,
            published_at: time(publication.published_at),
            deleted_at: time(publication.deleted_at),
            object_uri: publication.object_uri,
            representation: publication.representation
          }
        end
      }
    end

    def write_social
      following = actor ? Following.accepted_following_of(actor).includes(:followed_actor).map(&:followed_actor) : []
      followers = actor ? Following.accepted_followers_of(actor).includes(:follower_actor).map(&:follower_actor) : []
      entry("social/following.csv")
      @zip.write(Allure::CsvCell.line([ "Account address", "Show boosts", "Notify on new posts", "Languages" ]))
      following.each { @zip.write(Allure::CsvCell.line([ address(it), "true", "false", nil ])) }
      entry("social/followers.csv")
      @zip.write(Allure::CsvCell.line([ "Account address" ]))
      followers.each { @zip.write(Allure::CsvCell.line([ address(it) ])) }
      @counts["following"] = following.size
      @counts["followers"] = followers.size

      write_json("social/comments.json", comments)
      write_json("social/reactions.json", reactions)
    end

    def address(other)
      other.acct.presence || other.handle.to_s.delete_prefix("@")
    end

    def comments
      return [] unless actor

      Comment.where(actor:).includes(:workout, :remote_note, :parent).order(:published_at, :id).map do |comment|
        @counts["comments"] += 1
        {
          id: comment.to_param,
          uri: comment.uri,
          body: comment.body,
          status: comment.status,
          published_at: time(comment.published_at),
          deleted_at: time(comment.deleted_at),
          workout_id: comment.workout&.to_param,
          remote_note_uri: comment.remote_note&.uri,
          in_reply_to: comment.in_reply_to_uri,
          parent_uri: comment.parent&.uri
        }
      end
    end

    def reactions
      return [] unless actor

      Reaction.where(actor:).includes(:workout, :remote_note).order(:created_at, :id).map do |reaction|
        @counts["reactions"] += 1
        {
          kind: reaction.kind,
          created_at: time(reaction.created_at),
          undone_at: time(reaction.undone_at),
          workout_id: reaction.workout&.to_param,
          remote_note_uri: reaction.remote_note&.uri
        }
      end
    end

    def write_avatar
      return unless @user.avatar.attached?

      entry("avatar.webp", compression: Zip::Entry::STORED)
      @user.avatar.blob.open { |io| IO.copy_stream(io, @zip) }
    end

    def write_photos
      # Stream both files and metadata; do not hold a whole photo library in
      # memory. Even a failed photo's original belongs in the owner's export.
      Tempfile.create("allure-photo-index") do |index|
        index.write("[")
        first = true
        @user.workout_photos.includes(:workout, original_attachment: :blob).find_each do |photo|
          next unless photo.original.attached?

          name = "photos/#{photo.workout.to_param}/#{photo.to_param}#{Allure::Photos::Signature.extension(photo.original_content_type)}"
          entry(name, compression: Zip::Entry::STORED)
          photo.original.blob.open { |io| IO.copy_stream(io, @zip) }
          @counts["photos"] += 1
          index.write(",") unless first
          index.write(JSON.generate(id: photo.to_param, workout_id: photo.workout.to_param, file: name,
                                    caption: photo.caption, position: photo.position, status: photo.status))
          first = false
        end
        index.write("]")
        index.rewind
        entry("photos/index.json")
        IO.copy_stream(index, @zip)
      end
    end
  end
end
