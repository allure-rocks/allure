# frozen_string_literal: true

module Allure
  module ShortId
    ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".freeze
    LENGTH = 22
    UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    MAX_VALUE = (1 << 128) - 1

    module_function

    def encode(uuid)
      value = uuid.to_s
      raise ArgumentError, "invalid UUID" unless UUID_PATTERN.match?(value)

      number = value.delete("-").to_i(16)
      encoded = +""

      while number.positive?
        number, remainder = number.divmod(ALPHABET.length)
        encoded.prepend(ALPHABET[remainder])
      end

      encoded.rjust(LENGTH, ALPHABET[0])
    end

    def decode(short_id)
      value = short_id.to_s
      raise ArgumentError, "invalid ShortUUID" unless value.length == LENGTH

      number = value.each_char.reduce(0) do |result, character|
        digit = ALPHABET.index(character)
        raise ArgumentError, "invalid ShortUUID" unless digit

        result * ALPHABET.length + digit
      end
      raise ArgumentError, "invalid ShortUUID" if number > MAX_VALUE

      hexadecimal = number.to_s(16).rjust(32, "0")
      uuid = [ 8, 4, 4, 4, 12 ].map { |length| hexadecimal.slice!(0, length) }.join("-")
      raise ArgumentError, "non-canonical ShortUUID" unless encode(uuid) == value

      uuid
    end
  end
end
