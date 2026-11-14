# frozen_string_literal: true

require "digest"
require "json"

module Federation
  module Outbox
    module CanonicalJson
      def self.call(value) = JSON.generate(sort(value))

      def self.digest(value) = Digest::SHA256.hexdigest(call(value))

      def self.sort(value)
        case value
        when Hash
          value.keys.map(&:to_s).sort.index_with do |key|
            source_key = value.key?(key) ? key : key.to_sym
            sort(value[source_key])
          end
        when Array
          value.map { sort(_1) }
        else
          value
        end
      end
      private_class_method :sort
    end
  end
end
