# frozen_string_literal: true

module Webhooks
  # The event catalogue's emitters (PLAN_API.md §11.2), one per fact, each
  # called where the fact happens. Payloads never carry geometry: a workout is
  # its list representation without free text, a publication its summary.
  module Events
    module_function

    def workout_created(workout)
      emit(workout.user, "workout.created", "workout.created:#{workout.uuid}") { { workout: workout_summary(workout) } }
    end

    # Once per analysis version, when every enrichment of the import settled,
    # judged as automatic publishing judges it.
    def workout_analyzed(workout)
      return unless any_endpoint?(workout.user)
      return unless Workouts::AutoPublicationReadiness.new(workout).ready?

      emit(workout.user, "workout.analyzed", "workout.analyzed:#{workout.uuid}:#{workout.analysis_version}") do
        { workout: workout_summary(workout.reload) }
      end
    end

    def workout_updated(workout, changed)
      changed = Array(changed).map(&:to_s).uniq.sort
      return if changed.empty?

      emit(workout.user, "workout.updated", "workout.updated:#{workout.uuid}:#{SecureRandom.uuid}") do
        { workout: workout_summary(workout.reload), changed: }
      end
    end

    # The fields a save really changed: a blank value becoming another blank
    # one (an empty form field over nil) is no change to announce.
    def changed_fields(saved_changes, fields)
      saved_changes.slice(*fields).filter_map do |field, (before, after)|
        field unless before.presence == after.presence
      end
    end

    def workout_deleted(user, workout_id)
      emit(user, "workout.deleted", "workout.deleted:#{workout_id}") { { workout_id: } }
    end

    def publication_activated(publication)
      user = publication.workout&.user
      emit(user, "publication.activated", "publication.activated:#{publication.uuid}") do
        { publication: publication_summary(publication) }
      end
    end

    # `reason`: deleted, replaced, operator, cancelled, workout_deleted.
    # The payload is taken now: the workout may be gone by the commit.
    def publication_withdrawn(publication, reason:, user: publication.workout&.user)
      data = { publication_id: publication.to_param, workout_id: publication.workout&.to_param,
               audience: publication.audience, reason: }
      emit(user, "publication.withdrawn", "publication.withdrawn:#{publication.uuid}") { data }
    end

    def auto_publication_failed(row, reason:)
      workout = row.workout
      emit(workout.user, "publication.auto_failed", "publication.auto_failed:#{row.id}") do
        { workout_id: workout.to_param, audience: row.audience, reason: reason.to_s }
      end
    end

    # A record changed holder to `workout`. `record` is a Record (a classic
    # type) or an EffortRecord (a standard distance).
    def record_achieved(record)
      workout = record.workout
      return unless workout

      data = { workout_id: workout.to_param, sport: record.sport.slug }
      key = if record.is_a?(EffortRecord)
        data.merge!(distance_key: record.distance_key, distance: Api::Rest::V1::Formats.number(record.distance_meters),
                    elapsed_time: record.duration_seconds)
        record.distance_key
      else
        data.merge!(record_type: record.record_type, value: Api::Rest::V1::Formats.number(record.value))
        record.record_type
      end
      emit(workout.user, "record.achieved",
           "record.achieved:#{record.sport.slug}:#{key}:#{workout.uuid}:#{data[:value] || data[:elapsed_time]}") { data }
    end

    # Recent workouts only: a matcher upgrade re-creates every effort, and a
    # backfill must not announce years of old outings.
    SEGMENT_EFFORT_WINDOW = 7.days

    def segment_efforts_created(workout, efforts)
      return if efforts.empty? || workout.created_at < SEGMENT_EFFORT_WINDOW.ago
      return unless any_endpoint?(workout.user)

      places = Segments::PersonalPlaces.new(user: workout.user, efforts:).call
      standings = Segments::Standings.new(segments: efforts.map(&:segment).uniq, viewer: workout.user).call
                                     .index_by { [ it.segment.id, it.sport.id ] }
      efforts.each do |effort|
        standing = standings[[ effort.segment_id, effort.sport_id ]]
        data = { segment_effort_id: effort.to_param, workout_id: workout.to_param, segment_id: effort.segment.to_param,
                 segment_name: effort.segment.name, elapsed_time: effort.elapsed_time, personal_place: places[effort.id],
                 rank: (standing.rank if standing&.ranked) }
        emit(workout.user, "segment_effort.created",
             "segment_effort.created:#{workout.uuid}:#{effort.segment.uuid}:#{effort.occurrence_index}") { data }
      end
    end

    NOTIFICATION_EVENTS = {
      "follow_request" => "follow.requested",
      "follow_accepted" => "follow.accepted",
      "reaction" => "reaction.created",
      "comment" => "comment.created",
      "participation_requested" => "participation.requested",
      "participation_confirmed" => "participation.confirmed",
      "import_connection_expired" => "import_connection.expired",
      "import_connection_revoked" => "import_connection.revoked"
    }.freeze

    # The social and connection events, from the notification of the same
    # fact (`Notifications::Create`), whatever the account's in-app switches.
    def from_notification(user:, kind:, actor:, subject:, payload:)
      type = NOTIFICATION_EVENTS[kind]
      return unless type && subject && any_endpoint?(user)

      data = notification_data(kind, actor, subject, payload)
      return unless data

      emit(user, type, "#{type}:#{subject.class.name}:#{subject.id}") { data }
    end

    def notification_data(kind, actor, subject, payload)
      author = Api::Rest::V1::SocialSerializers.account(actor) if actor
      case kind
      when "follow_request", "follow_accepted"
        { account: author }
      when "reaction"
        target = subject.workout || subject.remote_note
        { **target_ids(target), type: subject.kind, author: }
      when "comment"
        { comment_id: subject.to_param, **target_ids(subject.target), author:, reply_to_id: subject.parent&.to_param }
      when "participation_requested", "participation_confirmed"
        participation_data(subject, author)
      when "import_connection_expired", "import_connection_revoked"
        { provider: payload.to_h["provider"] || subject.try(:provider) }
      end
    end

    # A participation on a local workout names that workout; an invitation
    # received from another instance names the received note it is about
    # (PLAN_TOGETHER.md §7), and is always a credit.
    def participation_data(subject, author)
      id = Allure::ShortId.encode(subject.uuid)
      if subject.is_a?(RemoteParticipation)
        { participation_id: id, **target_ids(subject.remote_note), kind: "credit", account: author }
      else
        { participation_id: id, workout_id: subject.workout.to_param, kind: subject.kind, account: author }
      end
    end

    def target_ids(target)
      case target
      when Workout then { workout_id: target.to_param }
      when RemoteNote then { remote_note_id: Allure::ShortId.encode(target.uuid) }
      else {}
      end
    end

    def ping(endpoint)
      Emit.emit!(endpoint.user, "ping", "ping:#{endpoint.uuid}:#{SecureRandom.uuid}", Time.current,
                 -> { { webhook_id: endpoint.to_param } }, only: endpoint)
    end

    def workout_summary(workout)
      Api::Rest::V1::WorkoutSerializer.new(workout, detail: false).as_json
    end

    def publication_summary(publication)
      base = Allure::Federation.config.base_url
      {
        id: publication.to_param, workout_id: publication.workout&.to_param, audience: publication.audience,
        published_at: Api::Rest::V1::Formats.time(publication.published_at),
        links: { self: "#{base}/api/rest/v1/publications/#{publication.to_param}" }
      }
    end

    def any_endpoint?(user) = user.present? && user.webhook_endpoints.deliverable.exists?

    # Errors never break the fact that triggered the event.
    def emit(user, type, dedupe_key, &)
      return unless any_endpoint?(user)

      Emit.call(user:, type:, dedupe_key:, &)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: "Webhooks::Events", type: })
    end
  end
end
