# frozen_string_literal: true

module Federation
  class InboxesController < ProtocolController
    UNAVAILABLE_RETRY_AFTER = 300
    # Per client address, before any parsing (docs/dev/FEDERATION.md). Generous enough
    # for a large instance's shared-inbox bursts; the per-authority limits
    # stay in Inbox::Admission and Safety::ResolutionAttempts.
    PER_IP_LIMIT = 300
    PER_IP_WINDOW = 1.minute

    rate_limit to: PER_IP_LIMIT, within: PER_IP_WINDOW, by: -> { request.remote_ip }, name: "federation-inbox",
               with: -> { refuse_rate_limited }

    def create
      recipient = local_actor_for(params[:username])
      return refuse(:not_found, "unknown_recipient", "personal inbox owner is unknown") unless recipient && !recipient.tombstoned?

      admit!(recipient_actor: recipient)
    end

    def create_shared
      admit!
    end

    private

    def admit!(recipient_actor: nil)
      # Read one byte past the cap at most: an unbounded or endless body must
      # never be buffered whole before Admission rejects it. The admission
      # check stays as the defense-in-depth guard.
      @body = request.body.read(Inbox::Admission::MAX_BODY_BYTES + 1).to_s
      Inbox::Admission.new(
        method: request.request_method,
        path: request.path,
        content_type: request.media_type,
        headers: protocol_headers,
        body: @body,
        recipient_actor:
      ).call!
      head :accepted
    rescue Inbox::Admission::InvalidRequest => error
      refuse(:unauthorized, "invalid", error.message)
    rescue Inbox::Admission::UnknownRecipient => error
      refuse(:not_found, "unknown_recipient", error.message)
    rescue Inbox::Admission::Blocked => error
      refuse(:forbidden, "blocked", error.message)
    rescue Inbox::Admission::RateLimited => error
      response.set_header("Retry-After", error.retry_after.to_s)
      refuse(:too_many_requests, "rate_limited", error.message)
    rescue Inbox::Admission::Unavailable => error
      response.set_header("Retry-After", UNAVAILABLE_RETRY_AFTER.to_s)
      refuse(:service_unavailable, "unavailable", error.message)
    end

    def refuse_rate_limited
      response.set_header("Retry-After", PER_IP_WINDOW.to_i.to_s)
      refuse(:too_many_requests, "rate_limited", "inbound request rate limit exceeded for this address")
    end

    # A refusal is otherwise silent on this side while the sender only sees a
    # status: the reason and the claimed actor (never the body) go to the log,
    # and the reason to `allure_federation_inbox_refusals_total`.
    def refuse(status, reason, message)
      Rails.logger.warn(
        "[federation] inbox refused #{reason} (#{Rack::Utils.status_code(status)}): " \
        "#{loggable(message)} actor=#{claimed_actor || "-"}"
      )
      count_refusal(reason)
      head status
    end

    def claimed_actor
      document = JSON.parse(@body.to_s)
      actor = document["actor"] if document.is_a?(Hash)
      loggable(actor) if actor.is_a?(String)
    rescue JSON::ParserError
      nil
    end

    # Both values come from the unauthenticated request: the claimed actor is
    # the body's own string, and a parser message quotes the bytes it choked
    # on. A line break or an escape sequence in either would forge a log line,
    # so every control character is dropped before the value is logged.
    def loggable(value, limit: 200)
      value.to_s.scrub.gsub(/[[:cntrl:]]/, "").truncate(limit)
    end

    def count_refusal(reason)
      Yabeda.allure.federation_inbox_refusals_total.increment({ reason: })
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: "federation_inbox_refusals_total" })
    end
  end
end
