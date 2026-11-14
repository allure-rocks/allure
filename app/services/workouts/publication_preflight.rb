# frozen_string_literal: true

module Workouts
  class PublicationPreflight
    EXPECTED_ATTACHMENT_NAMES = %w[gpx route_image].freeze

    Issue = Data.define(:code, :resource_id, :identifier, :details)

    Result = Data.define(:publication_count, :issues) do
      def passed? = issues.empty?
    end

    def call
      publications = WorkoutPublication.order(:id).to_a
      issues = []

      publications.each do |publication|
        inspect_publication(publication, issues)
      end

      inspect_outbox_subjects(issues)
      inspect_attachments(publications, issues)

      Result.new(
        publication_count: publications.length,
        issues: issues.sort_by { |issue| issue_sort_key(issue) }.freeze
      )
    end

    private

    def inspect_publication(publication, issues)
      identifier = publication_identifier(publication)

      # A scheduled publication is frozen but has no external identity yet:
      # outbox activity before activation means the delay was bypassed.
      if publication.scheduled? && FederationOutboxEvent.exists?(workout_publication_id: publication.id)
        issues << issue(
          :scheduled_publication_with_outbox,
          publication,
          "scheduled publication must not carry outbox activity before activation"
        )
      end

      inspect_publication_actor(publication, identifier, issues)
      inspect_publication_identity(publication, identifier, issues)
      inspect_persisted_validity(publication, identifier, issues)
    end

    def inspect_publication_actor(publication, identifier, issues)
      workout = publication.workout
      if (publication.active? || publication.scheduled?) && workout.nil?
        issues << issue(
          :publication_without_workout,
          publication,
          "live publication does not resolve its source workout"
        )
      end

      actor = publication.actor
      unless actor
        issues << issue(
          :publication_without_local_actor,
          publication,
          "publication does not retain its local actor; preflight will not provision one"
        )
        return
      end

      invalid_reasons = []
      invalid_reasons << "actor is not local" unless actor.local?
      invalid_reasons << "actor is tombstoned" if actor.tombstoned?
      if workout
        user = workout.user
        invalid_reasons << "actor user does not own the source workout" unless actor.user_id == user&.id
        begin
          invalid_reasons << "actor URI does not match the configured local identity" unless user && actor.uri == user.actor_uri
          invalid_reasons << "actor URI is outside the configured local base URL" unless Allure::Federation.config.local_uri?(actor.uri)
        rescue URI::InvalidURIError, Allure::Federation::Config::InvalidBaseUrl
          invalid_reasons << "actor URI cannot be validated against the configured local identity"
        end
      else
        begin
          invalid_reasons << "actor URI is outside the configured local base URL" unless Allure::Federation.config.local_uri?(actor.uri)
        rescue URI::InvalidURIError, Allure::Federation::Config::InvalidBaseUrl
          invalid_reasons << "actor URI cannot be validated against the configured local identity"
        end
      end

      return if invalid_reasons.empty?

      issues << Issue.new(
        code: :publication_invalid_local_actor,
        resource_id: publication.id,
        identifier: identifier,
        details: invalid_reasons.join("; ")
      )
    end

    def inspect_publication_identity(publication, identifier, issues)
      expected_uri = WorkoutPublication.object_uri_for(publication.uuid)
      return if publication.object_uri == expected_uri

      issues << Issue.new(
        code: :publication_object_uri_mismatch,
        resource_id: publication.id,
        identifier: identifier,
        details: "object URI does not match the persisted publication UUID"
      )
    rescue ArgumentError, NoMethodError, URI::InvalidURIError, Allure::Federation::Config::InvalidBaseUrl
      issues << Issue.new(
        code: :publication_identity_invalid,
        resource_id: publication.id,
        identifier: identifier,
        details: "publication UUID or object URI cannot be validated"
      )
    end

    def inspect_persisted_validity(publication, identifier, issues)
      return if publication.valid?

      details = publication.errors.full_messages.map { |message| message.gsub(/\s+/, " ") }.join("; ")
      issues << Issue.new(
        code: :invalid_retained_publication,
        resource_id: publication.id,
        identifier: identifier,
        details: details.presence || "persisted publication does not satisfy model validations"
      )
    end

    def inspect_outbox_subjects(issues)
      FederationOutboxEvent.find_each(order: :asc) do |event|
        case event.subject_type
        when "WorkoutPublication"
          publication = WorkoutPublication.find_by(id: event.subject_id)
          explicit = event.workout_publication_id
          if event.subject_id.blank? || publication.nil?
            issues << Issue.new(
              code: :dangling_publication_outbox_subject,
              resource_id: event.id,
              identifier: event.activity_uri,
              details: "publication outbox event does not resolve its publication"
            )
          elsif explicit.blank? || explicit != event.subject_id
            issues << Issue.new(
              code: :dangling_publication_outbox_subject,
              resource_id: event.id,
              identifier: event.activity_uri,
              details: "publication outbox event does not carry its explicit publication subject"
            )
          elsif event.object_uri != publication.object_uri && !secondary_event?(event)
            issues << Issue.new(
              code: :publication_outbox_identity_mismatch,
              resource_id: event.id,
              identifier: event.activity_uri,
              details: "outbox object URI does not match its publication subject"
            )
          end
        when "Actor"
          actor = Actor.find_by(id: event.subject_id)
          if event.workout_publication_id.present?
            issues << Issue.new(
              code: :dangling_actor_outbox_subject,
              resource_id: event.id,
              identifier: event.activity_uri,
              details: "actor outbox event must not carry an explicit publication subject"
            )
          elsif event.subject_id.blank? || actor.nil?
            issues << Issue.new(
              code: :dangling_actor_outbox_subject,
              resource_id: event.id,
              identifier: event.activity_uri,
              details: "actor outbox event does not resolve its actor"
            )
          elsif event.object_uri != actor.uri && !secondary_event?(event)
            issues << Issue.new(
              code: :actor_outbox_identity_mismatch,
              resource_id: event.id,
              identifier: event.activity_uri,
              details: "outbox object URI does not match its actor subject"
            )
          end
        when "SegmentPublication"
          publication = SegmentPublication.find_by(id: event.subject_id)
          explicit = event.segment_publication_id
          if event.subject_id.blank? || publication.nil?
            issues << Issue.new(
              code: :dangling_segment_publication_outbox_subject,
              resource_id: event.id,
              identifier: event.activity_uri,
              details: "segment publication outbox event does not resolve its publication"
            )
          elsif explicit.blank? || explicit != event.subject_id
            issues << Issue.new(
              code: :dangling_segment_publication_outbox_subject,
              resource_id: event.id,
              identifier: event.activity_uri,
              details: "segment publication outbox event does not carry its explicit publication subject"
            )
          elsif event.object_uri != publication.object_uri
            issues << Issue.new(
              code: :segment_publication_outbox_identity_mismatch,
              resource_id: event.id,
              identifier: event.activity_uri,
              details: "outbox object URI does not match its segment publication subject"
            )
          end
        else
          issues << Issue.new(
            code: :unsupported_outbox_subject,
            resource_id: event.id,
            identifier: event.activity_uri,
            details: "outbox event has an unsupported subject type"
          )
        end
      end
    end

    # An event that rides on a publication without being it. A comment's
    # Create or Delete names the comment, not its subject: the owner's rides
    # on its publication, a reader's is its author's own activity
    # (PLAN_COMMENTS.md §6.1). The host's relay — an Announce and its Undo —
    # and an owner's participation Invite and its Undo (PLAN_TOGETHER.md §7)
    # name the publishing actor itself, whose identity mints them (§6.6). The
    # identity is checked structurally, because the comment or participation
    # row goes with its workout while the event stays.
    def secondary_event?(event)
      case event.activity_type
      when "Create", "Delete" then Comment.local_uri?(event.object_uri)
      when "Announce", "Undo", "Invite" then event.subject_type == "WorkoutPublication" && event.object_uri == event.actor&.uri
      else false
      end
    end

    def inspect_attachments(publications, issues)
      publication_by_id = publications.index_by(&:id)
      attachments = ActiveStorage::Attachment
        .where(record_type: "WorkoutPublication")
        .order(:record_id, :name, :id)
        .to_a
      grouped = Hash.new { |hash, key| hash[key] = [] }

      attachments.each do |attachment|
        publication = publication_by_id[attachment.record_id]
        unless publication
          issues << Issue.new(
            code: :orphan_publication_attachment,
            resource_id: attachment.id,
            identifier: "record_id=#{attachment.record_id}/#{attachment.name}",
            details: "attachment does not resolve its publication"
          )
          next
        end

        unless EXPECTED_ATTACHMENT_NAMES.include?(attachment.name)
          issues << Issue.new(
            code: :unexpected_publication_attachment,
            resource_id: attachment.id,
            identifier: publication_identifier(publication),
            details: "publication has an unexpected attachment name"
          )
          next
        end

        grouped[[ publication.id, attachment.name ]] << attachment
      end

      publications.each do |publication|
        EXPECTED_ATTACHMENT_NAMES.each do |name|
          inspect_attachment_pair(publication, name, grouped[[ publication.id, name ]], issues)
        end
      end
    end

    def inspect_attachment_pair(publication, name, attachments, issues)
      direct_reference = publication.public_send("sanitized_#{name}_blob_id")
      return if direct_reference.blank? && attachments.empty?

      identifier = publication_identifier(publication)
      if direct_reference.blank?
        issues << Issue.new(
          code: :publication_attachment_without_reference,
          resource_id: publication.id,
          identifier: identifier,
          details: "#{name} attachment exists without its immutable blob reference"
        )
      elsif attachments.length != 1
        issues << Issue.new(
          code: :publication_attachment_count_mismatch,
          resource_id: publication.id,
          identifier: identifier,
          details: "#{name} has #{attachments.length} attachment rows; exactly one is required"
        )
      elsif attachments.first.blob_id != direct_reference
        issues << Issue.new(
          code: :publication_attachment_reference_mismatch,
          resource_id: publication.id,
          identifier: identifier,
          details: "#{name} attachment does not match its immutable blob reference"
        )
      end
    end

    def issue(code, publication, details)
      Issue.new(
        code:,
        resource_id: publication.id,
        identifier: publication_identifier(publication),
        details:
      )
    end

    def publication_identifier(publication)
      publication.uuid.presence || "id=#{publication.id}"
    end

    def issue_sort_key(issue)
      [ issue.code.to_s, issue.resource_id.to_i, issue.identifier.to_s, issue.details.to_s ]
    end
  end
end
