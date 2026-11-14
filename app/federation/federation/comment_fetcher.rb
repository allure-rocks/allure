# frozen_string_literal: true

require "json"

module Federation
  # Fetches a relayed comment from its author's own instance (PLAN_COMMENTS.md
  # §7.5): the thread host could otherwise put any words in any actor's name.
  # The GET is signed by the local recipient and bounded like any object
  # fetch. A refusal — the author's instance does not serve the comment — is
  # final; an unreachable instance is worth another try.
  class CommentFetcher
    class Refused < StandardError; end
    class Unavailable < StandardError; end

    MAX_BYTES = Parsers::RemoteComment::MAX_RAW_BYTES
    READ_TIMEOUT = 10
    TOTAL_TIMEOUT = 15

    def initialize(signer:, client: nil)
      @signer = signer
      @client = client || Transport::Client.new
    end

    def call(uri)
      response = SignedFetcher.new(actor: @signer, client: @client).get(
        uri, accept: Allure::Federation::MediaTypes::ACTIVITY_PUB, max_bytes: MAX_BYTES,
             read_timeout: READ_TIMEOUT, total_timeout: TOTAL_TIMEOUT
      )
      status = response.status.to_i
      raise Unavailable, "the author's instance answered HTTP #{status}" if status >= 500 || status.in?([ 408, 429 ])
      raise Refused, "the author's instance answered HTTP #{status}" unless status.between?(200, 299)

      document = JSON.parse(response.body.to_s)
      raise Refused, "the author's copy is not an object" unless document.is_a?(Hash)

      document
    rescue JSON::ParserError
      raise Refused, "the author's copy is not JSON"
    rescue Transport::SsrfGuard::UnsafeUri, Transport::Client::ResponseTooLarge, Transport::Client::TooManyRedirects,
           Transport::Client::UnsafeRedirect => error
      raise Refused, error.message
    rescue Transport::Client::NetworkError, Transport::Client::ResponseTimeout => error
      raise Unavailable, error.message
    end
  end
end
