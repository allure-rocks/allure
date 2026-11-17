# frozen_string_literal: true

module Api
  module Rest
    module V1
      # `Idempotency-Key` on a POST (docs/dev/API.md). The first response is
      # kept 24 hours per (token, key); a retry with the same request gets it
      # back with `Idempotency-Replayed: true`. The same key on a different
      # request is refused, and so is a retry while the first is still running.
      # A server error or a rate-limit refusal is not kept, so it can be
      # retried with the same key.
      #
      # An action opts in with `idempotent only: …`, declared after its
      # `require_scope`, so authorization runs before a key is claimed.
      module Idempotency
        extend ActiveSupport::Concern

        HEADER = "Idempotency-Key"
        NOT_KEPT = [ 429 ].freeze

        class_methods do
          def idempotent(**options)
            around_action :with_idempotency, **options
          end
        end

        private

        def with_idempotency
          key = request.headers[HEADER]
          return yield if key.nil?
          unless key.length.between?(1, 255)
            return render_problem(:bad_request, "invalid_parameter",
                                  detail: "The Idempotency-Key header must be 1 to 255 characters.")
          end

          digest = request_fingerprint
          record = claim_idempotency_key(key, digest)
          return replay_or_refuse(record, digest) unless record.previously_new_record?

          begin
            yield
          rescue StandardError
            record.destroy
            raise
          end
          keep_response(record)
        end

        def claim_idempotency_key(key, digest)
          scope = ApiIdempotencyKey.where(api_token: Current.api_token, key:)
          scope.expired.delete_all
          scope.create_or_find_by!(key:) do |record|
            record.request_digest = digest
            record.expires_at = ApiIdempotencyKey::TTL.from_now
          end
        end

        def replay_or_refuse(record, digest)
          if record.request_digest != digest
            render_problem(:unprocessable_content, "idempotency_key_reused")
          elsif !record.completed?
            render_problem(:conflict, "idempotency_key_in_progress")
          else
            record.response_headers.each { |name, value| response.headers[name] = value }
            response.headers["Idempotency-Replayed"] = "true"
            render body: record.response_body, status: record.response_status,
                   content_type: record.response_headers["Content-Type"]
          end
        end

        def keep_response(record)
          if response.status >= 500 || NOT_KEPT.include?(response.status)
            record.destroy
          else
            headers = ApiIdempotencyKey::REPLAYED_HEADERS.filter_map { |name| [ name, response.headers[name] ] if response.headers[name] }
            record.update!(response_status: response.status, response_headers: headers.to_h, response_body: response.body)
          end
        end

        # The method, the path, the query and the body; an uploaded file
        # counts by its name and its bytes' digest.
        def request_fingerprint
          payload = [ request.request_method, request.path, request.query_string, canonical(request.request_parameters) ]
          Digest::SHA256.hexdigest(JSON.generate(payload))
        end

        def canonical(value)
          case value
          when Hash then value.keys.map(&:to_s).sort.map { [ it, canonical(value[it]) ] }
          when Array then value.map { canonical(it) }
          when ActionDispatch::Http::UploadedFile
            [ "file", value.original_filename, Digest::SHA256.file(value.tempfile.path).hexdigest ]
          else value
          end
        end
      end
    end
  end
end
