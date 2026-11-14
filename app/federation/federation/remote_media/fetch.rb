# frozen_string_literal: true

module Federation
  module RemoteMedia
    # Fetches one attachment descriptor: signed GET, verification, caching, and
    # derived remote geometry. Permanent failures become unavailable/failed;
    # transient ones retry with capped backoff until the attempt cap.
    class Fetch
      MAX_ATTEMPTS = 5
      RETRY_BASE = 5.minutes
      RETRY_CAP = 24.hours
      RETRYABLE_STATUSES = [ 408, 425, 429 ].freeze

      def initialize(attachment:, client: nil, now: Time.current)
        @attachment = attachment
        @now = now
        @client = client
      end

      def call!
        return unless claim!

        owner = @attachment.owner
        return mark_unavailable("owner is not active") unless owner.active?
        return mark_unavailable("domain is blocked") if Safety::Blocks.blocked_domain?(owner.source_domain)
        return mark_unavailable("actor is blocked") if Safety::Blocks.blocked_actor?(owner.actor.uri)
        # The GET below is signed with a local actor's key: never let a stored
        # descriptor point that signature at any authority but the author's.
        return mark_unavailable("attachment authority does not match the source domain") unless same_authority?(owner)

        actor = signer_actor(owner)
        return mark_unavailable("no active recipient") unless actor

        response = signed_get(actor)
        handle_response(response)
      rescue Transport::Client::ResponseTimeout, Transport::Client::NetworkError => error
        schedule_retry(error)
      rescue Transport::Client::ResponseTooLarge => error
        mark_failed(error.message)
      rescue Transport::SsrfGuard::UnsafeUri, Transport::Client::UnsafeRedirect => error
        mark_unavailable(error.message)
      rescue Signature::Signer::InvalidActor => error
        mark_unavailable(error.message)
      rescue Verifier::InvalidContent => error
        mark_unavailable(error.message)
      end

      private

      def claim!
        @attachment.with_lock do
          return false if @attachment.status.in?(%w[cached purged unavailable])
          return false if @attachment.attempts >= MAX_ATTEMPTS

          @attachment.update!(
            status: "fetching",
            attempts: @attachment.attempts + 1,
            next_attempt_at: nil,
            last_error: nil
          )
        end
        true
      end

      def same_authority?(owner)
        authority = Allure::Federation::Authority.domain(@attachment.remote_url)
        authority.present? && authority.casecmp?(owner.source_domain.to_s)
      end

      def signer_actor(owner)
        owner.recipients.active.includes(:recipient_actor).order(:id).first&.recipient_actor
      end

      def signed_get(actor)
        accept = @attachment.kind == "gpx" ? Allure::Federation::MediaTypes::GPX : "image/png"
        max_bytes = @attachment.kind == "gpx" ? Verifier::MAX_GPX_BYTES : Verifier::MAX_IMAGE_BYTES
        SignedFetcher.new(actor:, client: @client).get(@attachment.remote_url, accept:, max_bytes:)
      end

      def handle_response(response)
        status = response.status.to_i
        if status.between?(200, 299)
          process_success(response.body)
        elsif status >= 500 || RETRYABLE_STATUSES.include?(status)
          schedule_retry("remote HTTP #{status}")
        else
          mark_unavailable("remote HTTP #{status}")
        end
      end

      def process_success(body)
        verified = Verifier.new(kind: @attachment.kind).call(body)
        processor = @attachment.kind == "gpx" ? GpxProcessor : ImageProcessor
        processor.new(attachment: @attachment, body:, verified:, now: @now).call
        @attachment
      end

      def schedule_retry(error)
        message = error.respond_to?(:message) ? error.message : error.to_s
        return mark_failed(message) if @attachment.attempts >= MAX_ATTEMPTS

        delay = [ RETRY_BASE * (2**[ @attachment.attempts - 1, 0 ].max), RETRY_CAP ].min
        @attachment.update!(
          status: "failed",
          next_attempt_at: @now + delay,
          last_error: message.to_s.truncate(500)
        )
        @attachment.fetch_job_class
          .set(wait_until: @attachment.next_attempt_at)
          .perform_later(@attachment.id, @attachment.source_domain)
      end

      def mark_unavailable(reason)
        @attachment.update!(status: "unavailable", next_attempt_at: nil, last_error: reason.to_s.truncate(500))
        @attachment
      end

      def mark_failed(reason)
        @attachment.update!(status: "failed", next_attempt_at: nil, last_error: reason.to_s.truncate(500))
        @attachment
      end
    end
  end
end
