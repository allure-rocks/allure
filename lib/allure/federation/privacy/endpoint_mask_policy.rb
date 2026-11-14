# frozen_string_literal: true

module Allure
  module Federation
    module Privacy
      class EndpointMaskPolicy
        class UnsatisfiedEndpoint < StandardError
          attr_reader :endpoint

          def initialize(endpoint)
            @endpoint = endpoint
            super("active privacy zones do not cover the masked #{endpoint} endpoint")
          end
        end

        def initialize(segments:, zones:, mask_start:, mask_finish:)
          @segments = segments
          @zones = zones
          @mask_start = mask_start
          @mask_finish = mask_finish
        end

        def call
          validate_segments!
          ensure_covered!(:start, @segments.first.first) if @mask_start == true
          ensure_covered!(:finish, @segments.last.last) if @mask_finish == true
          true
        end

        private

        def validate_segments!
          unless @segments.is_a?(Array) && @segments.any? && @segments.all? { |segment| segment.is_a?(Array) && segment.length >= 2 }
            raise ZoneFilter::InvalidInput, "at least one route segment is required"
          end
        end

        def ensure_covered!(endpoint, coordinate)
          covered = ZoneFilter.new(segments: @segments, zones: @zones).covered?(coordinate)
          raise UnsatisfiedEndpoint, endpoint unless covered
        end
      end
    end
  end
end
