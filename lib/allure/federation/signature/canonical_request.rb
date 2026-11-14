# frozen_string_literal: true

module Allure
  module Federation
    module Signature
      class CanonicalRequest
        REQUIRED_HEADERS = %w[(request-target) host date digest].freeze

        def initialize(method:, path:, headers:, signed_headers:)
          @method = method.to_s.downcase
          @path = path.to_s
          @headers = headers.to_h.transform_keys { |key| key.to_s.downcase }
          @signed_headers = signed_headers.map { |header| header.to_s.downcase }
        end

        def call
          validate!

          @signed_headers.map do |header|
            "#{header}: #{value_for(header)}"
          end.join("\n")
        end

        private

        def validate!
          raise ArgumentError, "request path must be absolute" unless @path.start_with?("/")
          raise ArgumentError, "request path must not contain a fragment" if @path.include?("#")
          raise ArgumentError, "signed headers must be unique" unless @signed_headers.uniq == @signed_headers
          raise ArgumentError, "required signed header is missing" unless REQUIRED_HEADERS.all? { @signed_headers.include?(_1) }
        end

        def value_for(header)
          return "#{@method} #{@path}" if header == "(request-target)"

          value = @headers[header]
          raise ArgumentError, "signed header is missing" if value.blank?

          value.to_s.strip
        end
      end
    end
  end
end
