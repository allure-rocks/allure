# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

module Allure
  module Assistant
    # The single provider seam (docs/dev/AI.md §2): an OpenAI-compatible
    # chat-completions endpoint, typically a LiteLLM proxy. It is
    # framework-independent and uses Net::HTTP only.
    #
    # `complete` sends one non-streaming call and returns a Result. The
    # response format is either a JSON Schema or absent: the reference
    # endpoint rejects `json_object` outright, and a refusal of `json_schema`
    # is retried once without it (prompt-only mode), because some engines only
    # answer when the schema stays in the prompt.
    class Client
      class Error < StandardError; end

      # 429, a 5xx, a transport failure or a timeout: the job retries.
      class UnavailableError < Error; end

      # A terminal rejection: a 4xx that does not name the response format.
      class InvalidRequestError < Error; end

      # A 2xx answer that is not a JSON object, or carries no usable content.
      class MalformedResponseError < Error; end

      CHAT_PATH = "/v1/chat/completions"
      # Always sent: the reference endpoint returned no answer at all on a
      # schema it could not close without a completion limit.
      MAX_TOKENS = 1_200
      DEFAULT_TEMPERATURE = 0.3
      DEFAULT_TIMEOUT = 300
      USER_AGENT = "Allure (workout summary)"
      OPEN_TIMEOUT = 10
      TOTAL_GRACE = 30
      MAX_RESPONSE_BYTES = 1 * 1024 * 1024
      # What the caller owns; AI_REQUEST_OPTIONS may not override it.
      RESERVED_KEYS = %w[model messages stream response_format].freeze
      # A refusal of the response format names one of these.
      FORMAT_REFUSAL = /response_format|json_schema/i

      Result = Data.define(:content, :model, :usage, :calls, :prompt_only) do
        def prompt_tokens = usage.fetch(:prompt_tokens, 0)
        def completion_tokens = usage.fetch(:completion_tokens, 0)
        def prompt_only? = prompt_only
      end

      attr_reader :base_url, :model, :timeout

      def initialize(base_url:, model:, api_key: nil, request_options: {}, timeout: DEFAULT_TIMEOUT)
        @base_url = base_url.to_s
        @model = model.to_s
        @api_key = api_key
        @request_options = request_options.is_a?(Hash) ? request_options : {}
        @timeout = timeout.to_i
      end

      # `schema` is a JSON Schema object, named for the provider by
      # `schema_name`. Without one the answer is JSON requested in the prompt.
      def complete(system:, user:, schema: nil, schema_name: "workout_summary",
                   max_tokens: MAX_TOKENS, temperature: DEFAULT_TEMPERATURE)
        body = body_for(system:, user:, schema:, schema_name:, max_tokens:, temperature:, format: !schema.nil?)
        begin
          return post(body, calls: 1, prompt_only: schema.nil?)
        rescue InvalidRequestError => error
          raise unless schema && error.message.match?(FORMAT_REFUSAL)
        end

        body = body_for(system:, user:, schema:, schema_name:, max_tokens:, temperature:, format: false)
        post(body, calls: 2, prompt_only: true)
      end

      private

      def body_for(system:, user:, schema:, schema_name:, max_tokens:, temperature:, format:)
        body = {
          "model" => model,
          "messages" => [
            { "role" => "system", "content" => system },
            { "role" => "user", "content" => user }
          ],
          "temperature" => temperature,
          "max_tokens" => max_tokens,
          "stream" => false
        }
        if format && schema
          body["response_format"] = {
            "type" => "json_schema",
            "json_schema" => { "name" => schema_name, "strict" => true, "schema" => schema }
          }
        end
        merge_request_options(body)
      end

      def merge_request_options(body)
        @request_options.each do |key, value|
          key = key.to_s
          next if RESERVED_KEYS.include?(key)

          body[key] = value
        end
        body
      end

      def post(body, calls:, prompt_only:)
        uri = URI.parse("#{base_url.chomp("/")}#{CHAT_PATH}")
        request = Net::HTTP::Post.new(uri)
        request["User-Agent"] = USER_AGENT
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}" if @api_key
        request.body = body.to_json

        Timeout.timeout(timeout + TOTAL_GRACE) do
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                                  open_timeout: OPEN_TIMEOUT, read_timeout: timeout) do |http|
            http.request(request) do |response|
              raw = read_body(response)
              return parse(raw, calls:, prompt_only:) if response.is_a?(Net::HTTPSuccess)

              message = error_message(raw, response)
              raise UnavailableError, message if retryable?(response)

              raise InvalidRequestError, message
            end
          end
        end
      rescue Error
        raise
      rescue StandardError => error
        raise UnavailableError, error.message
      end

      def retryable?(response) = response.code == "429" || response.is_a?(Net::HTTPServerError)

      def read_body(response)
        body = +""
        response.read_body do |chunk|
          body << chunk
          raise MalformedResponseError, "the answer exceeds #{MAX_RESPONSE_BYTES} bytes" if body.bytesize > MAX_RESPONSE_BYTES
        end
        body
      end

      def error_message(raw, response)
        parsed = JSON.parse(raw)
        error = parsed.is_a?(Hash) ? parsed["error"] : nil
        message = error.is_a?(Hash) ? error["message"] : error
        message.to_s.strip.presence || "HTTP #{response.code}"
      rescue JSON::ParserError
        raw.to_s.strip.first(300).presence || "HTTP #{response.code}"
      end

      def parse(raw, calls:, prompt_only:)
        json = JSON.parse(raw)
        raise MalformedResponseError, "the answer is not a JSON object" unless json.is_a?(Hash)

        message = json.dig("choices", 0, "message")
        content = message.is_a?(Hash) ? strip_reasoning(message["content"]) : nil
        raise MalformedResponseError, "the answer carries no content" if content.blank?

        Result.new(content:, model: answer_model(json), usage: answer_usage(json), calls:, prompt_only:)
      rescue JSON::ParserError
        raise MalformedResponseError, "the answer is not JSON"
      end

      def answer_model(json)
        value = json["model"].to_s.strip
        value.empty? ? model : value
      end

      def answer_usage(json)
        usage = json["usage"]
        usage = {} unless usage.is_a?(Hash)
        {
          prompt_tokens: usage["prompt_tokens"].to_i,
          completion_tokens: usage["completion_tokens"].to_i
        }
      end

      # A model that still reasons despite the operator's options returns its
      # thinking in the content (docs/dev/AI.md §2): it never reaches a member.
      def strip_reasoning(content)
        content.to_s.gsub(/.*?<\/think>\s*/m, "").strip
      end
    end
  end
end
