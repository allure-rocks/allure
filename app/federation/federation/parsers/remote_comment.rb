# frozen_string_literal: true

require "json"
require "time"
require "uri"

module Federation
  module Parsers
    # The strict Allure comment profile (PLAN_COMMENTS.md §7.2): an embedded
    # Note written by the sending actor, on the sender's own authority,
    # answering a publication or a comment through `inReplyTo`. Its content is
    # sanitized like a received note's and its text projection is bounded like
    # a local comment. Whole-document violations raise InvalidObject; a
    # malformed `published` is a warning. Tags, attachments, and unknown keys
    # stay in `raw` and are ignored — a `Mention` waits for a later annex.
    class RemoteComment
      class InvalidObject < StandardError; end

      MAX_CONTENT_BYTES = 10_000
      MAX_RAW_BYTES = 64 * 1024
      MAX_WARNINGS = 10

      Value = Data.define(
        :object_uri, :attributed_to, :in_reply_to, :context, :body, :content_html, :published_at, :warnings, :raw
      )

      def initialize(activity)
        @activity = activity.is_a?(Hash) ? activity : {}
        @object = @activity["object"]
        @warnings = []
      end

      def call
        validate_document!
        content_html = sanitized_content
        body = RemoteText.text(content_html).to_s
        raise InvalidObject, "comment text is empty" if body.blank?
        raise InvalidObject, "comment text is too long" if body.length > Comment::MAX_BODY_LENGTH

        Value.new(
          object_uri: @object_uri,
          attributed_to: @activity["actor"],
          in_reply_to: @in_reply_to,
          context: parse_context,
          body:,
          content_html:,
          published_at: parse_published,
          warnings: @warnings.dup,
          raw: @object
        )
      end

      private

      def validate_document!
        raise InvalidObject, "activity object must be embedded" unless @object.is_a?(Hash)
        raise InvalidObject, "object type must be Note" unless @object["type"] == "Note"

        actor = @activity["actor"].to_s
        raise InvalidObject, "activity actor is missing" if actor.blank?
        raise InvalidObject, "object attribution does not match the actor" unless @object["attributedTo"] == actor

        @object_uri = absolute_uri(@object["id"])
        raise InvalidObject, "object id is invalid" unless @object_uri

        actor_authority = Allure::Federation::Authority.domain(actor)
        object_authority = Allure::Federation::Authority.domain(@object_uri)
        raise InvalidObject, "object authority does not match the author" unless actor_authority && actor_authority == object_authority

        @in_reply_to = absolute_uri(@object["inReplyTo"])
        raise InvalidObject, "inReplyTo is invalid" unless @in_reply_to

        raise InvalidObject, "comment is too large" if JSON.generate(@object).bytesize > MAX_RAW_BYTES
      end

      def sanitized_content
        content = @object["content"]
        raise InvalidObject, "content is missing" unless content.is_a?(String) && content.present?
        raise InvalidObject, "content is too large" if content.bytesize > MAX_CONTENT_BYTES

        RemoteText.sanitize(content).to_s
      end

      # The publication the thread hangs on (§6.2); optional, and only a hint
      # for a reply whose parent this instance never saw.
      def parse_context
        value = @object["context"]
        return if value.nil?

        uri = absolute_uri(value)
        warn("invalid context") unless uri
        uri
      end

      def parse_published
        value = @object["published"]
        return if value.nil?

        raw = value.to_s
        return Time.iso8601(raw).utc if raw.include?("T")

        warn("invalid published")
        nil
      rescue ArgumentError, TypeError
        warn("invalid published")
        nil
      end

      def absolute_uri(value)
        return unless value.is_a?(String) && value.present?

        parsed = URI.parse(value)
        valid = parsed.scheme.in?(%w[http https]) && parsed.host.present? &&
          parsed.userinfo.blank? && parsed.query.blank? && parsed.fragment.blank?
        valid ? value : nil
      rescue URI::InvalidURIError, URI::InvalidComponentError
        nil
      end

      def warn(message)
        @warnings << message unless @warnings.length >= MAX_WARNINGS
      end
    end
  end
end
