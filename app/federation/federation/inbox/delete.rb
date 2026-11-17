# frozen_string_literal: true

require "uri"

module Federation
  module Inbox
    # Processes a Delete for a received note or course: durable tombstone,
    # entitlement withdrawal, and synchronous location redaction. A Delete for
    # an object never seen locally creates a tombstone so a later Create cannot
    # resurrect it (docs/dev/FEDERATION.md, §8.6; PLAN_SEGMENTS_FEDERATION.md §10.4).
    class Delete
      def initialize(item:, activity:, now: Time.current, outbox_events: [])
        @item = item
        @activity = activity
        @now = now
        @outbox_events = outbox_events
      end

      def call!
        raise Rejected, "activity actor does not match the sender" unless @activity["actor"] == @item.actor_uri
        return process_actor_deletion! if actor_deletion?

        object_uri = resolve_object_uri
        comment = ::Comment.find_by(uri: object_uri)
        return delete_comment!(comment) if comment
        # A comment tombstone needs a thread, which a bare Delete never names:
        # an unknown comment is refused instead (PLAN_COMMENTS.md §7.3).
        raise Rejected, "comment is unknown" if comment_path?(object_uri)

        model = object_model(object_uri)
        record = model.find_by(object_uri:)
        return create_tombstone!(model, object_uri) unless record

        raise Rejected, "object author does not match" unless record.actor.uri == @item.actor_uri
        return record if record.deleted?

        model.transaction(requires_new: true) do
          record.mark_deleted!(at: @now)
          record.recipients.active.find_each { |recipient| recipient.withdraw!(reason: "deleted", at: @now) }
          RemoteMedia::Purge.new(owner: record, now: @now).call!
          Participations::RemoteWithdrawal.close_pending!(record, at: @now) if record.is_a?(RemoteNote)
        end
        record
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
        raise Rejected, "invalid remote delete: #{error.message}"
      end

      private

      # An actor Delete carries an embedded Tombstone whose id is the sender's
      # own actor URI (docs/dev/FEDERATION.md). It is handled apart from object
      # tombstones: the author is tombstoned, every entitlement it delivered is
      # withdrawn, and its notes and courses lose their media and location data.
      def actor_deletion?
        object = @activity["object"]
        return true if object.is_a?(Hash) && object["type"] == "Tombstone" && object["id"] == @item.actor_uri

        object.is_a?(String) && object == @item.actor_uri
      end

      def process_actor_deletion!
        actor = Actor.find_by(uri: @item.actor_uri)
        raise Rejected, "author is not cached" unless actor&.remote?
        return actor if actor.tombstoned?

        Actor.transaction(requires_new: true) do
          actor.tombstone!(at: @now)
          Notifications::Withdraw.new(actor:).call!
          removal = Comments::AuthorRemoval.new(actors: actor, reason: "actor_deleted", now: @now)
          removal.call!
          @outbox_events.concat(removal.outbox_events)
          [ RemoteNote, RemoteSegment ].each do |model|
            model.where(actor:).find_each do |record|
              record.recipients.active.find_each { |recipient| recipient.withdraw!(reason: "deleted", at: @now) }
              RemoteMedia::Purge.new(owner: record, now: @now).call!(force: true)
            end
          end
          Participations::RemoteWithdrawal.close_pending!(RemoteNote.where(actor:), at: @now)
          # The deleted account took part in this instance's workouts: those
          # participations end with it (docs/dev/SHARED-ACTIVITIES.md).
          WorkoutParticipation.active.where(participant_actor: actor).find_each do |participation|
            participation.update!(withdrawn_at: @now)
            Notifications::Withdraw.new(subject: participation).call!
          end
          Following.end_with!(actor, at: @now)
        end
        actor
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
        raise Rejected, "invalid remote actor delete: #{error.message}"
      end

      def resolve_object_uri
        object = @activity["object"]
        value = object.is_a?(Hash) ? object["id"] : object
        raise Rejected, "object id is missing" unless value.is_a?(String) && value.present?

        parsed = URI.parse(value)
        valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
          parsed.userinfo.blank? && parsed.query.blank? && parsed.fragment.blank?
        raise Rejected, "object id is invalid" unless valid

        # A Delete can only tombstone an object its sender's authority owns.
        # Without this an actor could tombstone another instance's known object
        # URI and permanently reject the real author's later Create, exactly as
        # the Create parser binds attributedTo to the author authority.
        sender_authority = Allure::Federation::Authority.domain(@item.actor_uri)
        object_authority = Allure::Federation::Authority.domain(value)
        unless sender_authority && sender_authority == object_authority
          raise Rejected, "object authority does not match the sender"
        end

        value
      rescue URI::InvalidURIError, URI::InvalidComponentError
        raise Rejected, "object id is invalid"
      end

      def object_model(object_uri)
        object_uri.include?("/api/v1/segment/") ? RemoteSegment : RemoteNote
      end

      # The author takes their comment back, here as on their own instance; a
      # thread hosted here stops relaying it.
      def delete_comment!(comment)
        raise Rejected, "comment author does not match" unless comment.actor.uri == @item.actor_uri
        return comment unless comment.active?

        ::Comment.transaction(requires_new: true) do
          comment.mark_deleted!(at: @now)
          Comments::Notifier.withdraw!(comment)
          undo = Outbox::CommentUnannounce.new(comment:, now: @now).call! if comment.workout
          @outbox_events << undo if undo
        end
        comment
      end

      def comment_path?(object_uri)
        URI.parse(object_uri).path.to_s.start_with?(::Comment::OBJECT_PATH)
      rescue URI::InvalidURIError, URI::InvalidComponentError
        false
      end

      def create_tombstone!(model, object_uri)
        author = Actor.find_by(uri: @item.actor_uri)
        raise Rejected, "author is not cached" unless author&.remote?

        object = @activity["object"]
        raw = object.is_a?(Hash) ? object : { "id" => object_uri }

        attributes = {
          actor: author,
          object_uri:,
          activity_uri: @item.activity_uri,
          audience: "public",
          status: "deleted",
          deleted_at: @now,
          received_at: @item.created_at || @now,
          source_domain: Allure::Federation::Authority.domain(author.uri),
          representation: { "redacted" => true },
          route_metadata: { "redacted" => true },
          location_data_purged_at: @now,
          raw:,
          warnings: []
        }
        if model == RemoteSegment
          # A Delete carries no course body; the identity survives with an
          # empty name and a redacted representation.
          attributes.merge!(name: "", kind: "segment", published_at: @now)
        end

        model.create!(attributes)
      end
    end
  end
end
