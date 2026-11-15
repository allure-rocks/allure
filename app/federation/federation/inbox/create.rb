# frozen_string_literal: true

module Federation
  module Inbox
    # Processes one embedded public object into a RemoteNote or a RemoteSegment
    # plus one entitlement for the receiving local actor. The object path
    # selects the course or workout receipt. Idempotent by object identity; a
    # tombstoned object always wins (docs/dev/FEDERATION.md,
    # PLAN_SEGMENTS_FEDERATION.md §10.3).
    class Create
      def initialize(item:, activity:, now: Time.current)
        @item = item
        @activity = activity
        @now = now
      end

      def call!
        raise Rejected, "activity actor does not match the sender" unless @activity["actor"] == @item.actor_uri

        value = object_parser.new(@activity).call
        author = remote_actor!
        audience = validate_audience!(value, author)
        require_follow!(author)

        record = find_or_create_record(value, author, audience)
        upsert_entitlement!(record)
        record
      rescue Parsers::RemoteNote::InvalidObject, Parsers::RemoteSegment::InvalidObject => error
        raise Rejected, error.message
      rescue ActiveRecord::RecordInvalid => error
        raise Rejected, "invalid remote object: #{error.record.errors.full_messages.to_sentence}"
      end

      private

      def remote_actor!
        actor = Actor.find_by(uri: @item.actor_uri)
        raise Rejected, "author is not available" unless actor&.remote? && !actor.tombstoned?
        raise Rejected, "author is blocked" if Safety::Blocks.blocked?(actor.uri)

        actor
      end

      # A publication reaches the accounts that follow its author, never one
      # it merely names (docs/dev/FEDERATION.md): otherwise any remote actor could put
      # a note, its media fetches and the invitations it enables in a stranger's
      # feed. Allure itself never addresses a publication directly.
      def require_follow!(author)
        return if Following.accepted_between(follower_actor: @item.recipient_actor, followed_actor: author).exists?

        raise Rejected, "recipient does not follow the author"
      end

      def validate_audience!(value, author)
        return "public" if value.audience.include?(object_parser::PUBLIC_AUDIENCE)

        followers_uri = author.raw.is_a?(Hash) ? author.raw["followers"] : nil
        if followers_uri.is_a?(String) && value.audience.include?(followers_uri)
          raise Rejected, "restricted audience is not enabled" unless Allure::Federation::Config.restricted_enabled?

          return "followers"
        end

        raise Rejected, "unsupported audience"
      end

      def find_or_create_record(value, author, audience)
        existing = record_class.find_by(object_uri: value.object_uri)
        if existing
          raise Rejected, "object author does not match" unless existing.actor_id == author.id
          raise Rejected, "object was already deleted" if existing.deleted?

          return existing
        end

        record_class.transaction(requires_new: true) do
          record = record_class.create!(attributes_for(value, author, audience))
          persist_attachments!(record, value.attachments)
          record
        end
      rescue ActiveRecord::RecordNotUnique
        # A concurrent delivery for another local recipient won the identity.
        record_class.find_by!(object_uri: value.object_uri)
      end

      def attributes_for(value, author, audience)
        shared = {
          actor: author,
          object_uri: value.object_uri,
          activity_uri: @item.activity_uri,
          audience:,
          published_at: value.published_at,
          received_at: @item.created_at || @now,
          source_domain: Allure::Federation::Authority.domain(author.uri),
          representation: representation_for(value),
          route_metadata: {},
          raw: value.raw,
          warnings: value.warnings,
          content_html: value.content_html,
          description: value.description,
          sport_label: value.sport_label
        }
        return shared.merge(title: value.title, started_at: value.started_at, metrics: value.metrics) unless course?

        shared.merge(
          name: value.name,
          kind: "segment",
          distance: value.metrics["distance"],
          ascent: value.metrics["ascent"],
          descent: value.metrics["descent"],
          average_grade: value.metrics["average_grade"]
        )
      end

      def representation_for(value)
        return note_representation_for(value) unless course?

        {
          "name" => value.name,
          "description" => value.description,
          "sport_slug" => value.sport_slug,
          "kind" => "segment",
          "distance" => value.metrics["distance"],
          "ascent" => value.metrics["ascent"],
          "descent" => value.metrics["descent"],
          "average_grade" => value.metrics["average_grade"],
          "match_tolerance" => value.metrics["match_tolerance"]&.to_i,
          "location" => value.location
        }.compact
      end

      def note_representation_for(value)
        {
          "title" => value.title,
          "description" => value.description,
          "sport_label" => value.sport_label,
          "started_at" => value.started_at&.iso8601,
          "metrics" => value.metrics,
          "record_types" => value.record_types.presence,
          "record_distances" => value.record_distances.presence,
          "device" => value.device,
          "commute" => value.commute,
          "weather" => value.weather,
          "comments_closed" => value.comments_closed,
          "location" => value.location
        }.compact
      end

      # A duplicate Create never reactivates a withdrawn entitlement: an
      # unfollow stays withdrawn for that object.
      def upsert_entitlement!(record)
        recipient = record.recipients.find_or_initialize_by(recipient_actor: @item.recipient_actor)
        return recipient if recipient.persisted?

        recipient.status = "active"
        recipient.inbox_item = @item
        recipient.save!
        recipient
      end

      def persist_attachments!(record, attachments)
        attachments.each do |attachment|
          record.attachments.find_or_create_by!(kind: attachment.kind, theme: attachment.theme) do |row|
            row.remote_url = attachment.remote_url
            row.media_type = attachment.media_type
            row.status = "pending"
          end
        end
      end

      def course? = object_uri.include?("/api/v1/segment/")

      def object_uri
        object = @activity["object"]
        uri = object.is_a?(Hash) ? object["id"] : object
        uri.to_s
      end

      def object_parser = course? ? Parsers::RemoteSegment : Parsers::RemoteNote
      def record_class = course? ? RemoteSegment : RemoteNote
    end
  end
end
