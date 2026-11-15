# frozen_string_literal: true

module Federation
  module Delivery
    class RecipientAuthorizer
      Result = Data.define(:allowed, :inbox_url, :reason) do
        def allowed? = !!allowed
      end

      # Statuses of a publication delivery whose recipient holds, or is about
      # to hold, the note a secondary event talks about.
      LIVE_PUBLICATION_DELIVERY_STATUSES = %w[pending delivering reconciling retrying delivered].freeze

      # The event a secondary Undo takes back, named by the nested object's
      # `id` among the same actor's events (PLAN_COMMENTS.md §9). Delivery
      # orders the Undo after it.
      def self.undone_event_for(event)
        object = event.payload.is_a?(Hash) ? event.payload["object"] : nil
        uri = object.is_a?(Hash) ? object["id"] : nil
        uri.present? ? FederationOutboxEvent.find_by(activity_uri: uri, actor_id: event.actor_id) : nil
      end

      def initialize(event:, actor:, client: nil)
        @event = event
        @actor = actor
        @client = client
      end

      def call
        return denied("recipient is missing") unless @actor
        return denied("recipient is not remote") unless @actor.remote?
        return denied("recipient is tombstoned") if @actor.tombstoned?
        return denied("recipient is blocked") if Safety::Blocks.blocked?(@actor.uri)

        if publication_event?
          authorize_publication_recipient
        else
          authorize_actor_event_recipient
        end
      end

      private

      def authorize_publication_recipient
        publication = publication_subject
        return authorize_secondary_recipient(publication) if secondary_event?(publication)

        if @event.activity_type == "Create"
          return denied("publication is not active") unless publication&.active?
          return denied("relationship is not accepted") unless follow_accepted?(@actor)
          return denied("audience and capability are incompatible") unless capability_allowed?(publication)
          return denied("recipient is not permitted by publication policy") unless policy_allowed?(publication)
          return denied("recipient is served a narrower publication") if served_narrower?(publication)
        else
          return denied("publication identity is not retained") unless publication
          return denied("recipient was not in the attempted Create set") unless attempted_recipient?(@actor.uri)
        end

        inbox = inbox_for(@actor)
        return denied("recipient has no safe destination") unless inbox_safe?(inbox)

        Result.new(allowed: true, inbox_url: inbox, reason: nil)
      end

      # An owner's comment, the host's relay of a comment, and an owner's
      # participation Invite ride on their publication without being it
      # (PLAN_COMMENTS.md §9, PLAN_TOGETHER.md §7): a Create, an Announce or an
      # Invite reaches only an instance that holds, or is being sent, the
      # publication, and still passes the publication's rules; a Delete
      # follows its own Create and an Undo the activity it undoes, like any
      # withdrawal. A follower accepted after the publication never received
      # the note and would refuse the comment.
      def authorize_secondary_recipient(publication)
        case @event.activity_type
        when "Create", "Announce", "Invite"
          return denied("publication is not active") unless publication.active?
          return denied("recipient does not hold the publication") unless publication_recipient?(publication)
          return denied("relationship is not accepted") unless follow_accepted?(@actor)
          return denied("audience and capability are incompatible") unless capability_allowed?(publication)
          return denied("recipient is not permitted by publication policy") unless policy_allowed?(publication)
        when "Undo"
          return denied("recipient was not in the undone activity's attempted set") unless undone_recipient?(@actor.uri)
        else
          return denied("recipient was not in the attempted Create set") unless attempted_recipient?(@actor.uri)
        end

        inbox = inbox_for(@actor)
        return denied("recipient has no safe destination") unless inbox_safe?(inbox)

        Result.new(allowed: true, inbox_url: inbox, reason: nil)
      end

      # One Note per peer (docs/dev/PUBLISHING.md): a recipient entitled to a
      # narrower active publication of the same workout — a promoted follower
      # when a followers publication sits beside the public one — receives that
      # one only. Decided at expansion: a Note already delivered stays.
      def served_narrower?(publication)
        return false unless publication.is_a?(WorkoutPublication) && publication.workout

        rank = WorkoutPublication.audience_rank(publication.audience)
        publication.workout.active_publications.where.not(id: publication.id).any? do |other|
          WorkoutPublication.audience_rank(other.audience) < rank && policy_allowed?(other)
        end
      end

      def authorize_actor_event_recipient
        inbox = inbox_for(@actor)
        return denied("recipient has no safe destination") unless inbox_safe?(inbox)

        Result.new(allowed: true, inbox_url: inbox, reason: nil)
      end

      def publication_event? = @event.subject_type.in?(%w[WorkoutPublication SegmentPublication])

      def secondary_event?(publication) = publication.present? && @event.object_uri != publication.object_uri

      def publication_recipient?(publication)
        create_event = withdrawal_for(publication).find_create_event(publication)
        return false unless create_event

        FederationDeliveryRecipient.joins(:delivery)
          .where(actor_uri: @actor.uri, status: "authorized")
          .where(federation_deliveries: { outbox_event_id: create_event.id, status: LIVE_PUBLICATION_DELIVERY_STATUSES })
          .exists?
      end

      def publication_subject
        return unless publication_event?

        if @event.subject_type == "SegmentPublication"
          SegmentPublication.find_by(id: @event.segment_publication_id || @event.subject_id)
        else
          WorkoutPublication.find_by(id: @event.workout_publication_id || @event.subject_id)
        end
      end

      def follow_accepted?(actor)
        return false if @event.actor.tombstoned?

        Following.accepted_between(follower_actor: actor, followed_actor: @event.actor).exists?
      end

      # A followers-only event leaves the instance only while restricted
      # federation is enabled, and then to a promoted peer only (docs/dev/FEDERATION.md
      # §13.3): the followers audience itself is always publishable for local
      # followers, so this is the switch's one outbound gate. Which inbox
      # receives the POST is a separate decision made by `inbox_for`:
      # `restricted_fetch` always uses the personal inbox even when the peer
      # advertises a shared one.
      def capability_allowed?(publication)
        return true unless followers_only_event?
        return false unless Allure::Federation::Config.restricted_enabled?

        @actor.capability_profile.in?(%w[restricted_fetch restricted_shared_inbox])
      end

      def followers_only_event?
        values = @event.audience.values.flatten
        values.include?(followers_collection_uri) && !values.include?(Outbox::Expander::PUBLIC_AUDIENCE)
      end

      def followers_collection_uri = "#{@event.actor.uri}/followers"

      def policy_allowed?(publication)
        policy_class, principal_class = if publication.is_a?(SegmentPublication)
          [ Segments::PublicationPolicy, Workouts::PublicationPrincipal ]
        else
          [ Workouts::PublicationPolicy, Workouts::PublicationPrincipal ]
        end
        policy_class.new(
          publication:,
          principal: principal_class.protocol(@actor)
        ).allowed?
      end

      def attempted_recipient?(actor_uri)
        create_event = FederationOutboxEvent.find_by(
          actor_id: @event.actor_id,
          object_uri: @event.object_uri,
          activity_type: "Create"
        )
        return true unless create_event

        recipient_uris_for(create_event).include?(actor_uri)
      end

      # An Undo names the activity it takes back; it goes only where that
      # activity was attempted.
      def undone_recipient?(actor_uri)
        undone = self.class.undone_event_for(@event)
        undone.present? && recipient_uris_for(undone).include?(actor_uri)
      end

      def recipient_uris_for(create_event)
        if @event.subject_type == "SegmentPublication"
          Segments::PublicationWithdrawal.recipient_uris_for(create_event)
        else
          Workouts::PublicationWithdrawal.recipient_uris_for(create_event)
        end
      end

      def withdrawal_for(publication)
        publication.is_a?(SegmentPublication) ? Segments::PublicationWithdrawal : Workouts::PublicationWithdrawal
      end

      def inbox_for(actor)
        if actor.capability_profile == "restricted_shared_inbox" && actor.shared_inbox_url.present?
          actor.shared_inbox_url
        else
          actor.inbox_url
        end
      end

      def inbox_safe?(inbox)
        return false if inbox.blank?

        @client&.validate_url(inbox)
        true
      rescue Transport::SsrfGuard::UnsafeUri
        false
      end

      def denied(reason) = Result.new(allowed: false, inbox_url: nil, reason:)
    end
  end
end
