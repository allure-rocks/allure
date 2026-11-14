# frozen_string_literal: true

module Api
  module Rest
    module V1
      # Opaque pagination cursors (PLAN_API.md §5). Encrypted rather than only
      # signed, so the internal row id they carry never reaches a client, and
      # bound to the ordering they were issued for.
      module Cursor
        class Invalid < StandardError; end

        PURPOSE = "api/rest/v1/cursor"

        module_function

        def encode(values, context:)
          encryptor.encrypt_and_sign(values, purpose: "#{PURPOSE}:#{context}")
        end

        def decode(cursor, context:)
          values = encryptor.decrypt_and_verify(cursor.to_s, purpose: "#{PURPOSE}:#{context}")
          raise Invalid unless values.is_a?(Array) && values.size == 2 && values.last.is_a?(Integer)

          values
        rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
          raise Invalid
        end

        # A JSON-safe, order-preserving form of a sort value.
        def dump(value)
          case value
          when Time, ActiveSupport::TimeWithZone then value.utc.iso8601(6)
          when BigDecimal then value.to_s("F")
          else value
          end
        end

        def encryptor
          @encryptor ||= ActiveSupport::MessageEncryptor.new(
            Rails.application.key_generator.generate_key(PURPOSE, ActiveSupport::MessageEncryptor.key_len),
            url_safe: true
          )
        end
      end
    end
  end
end
