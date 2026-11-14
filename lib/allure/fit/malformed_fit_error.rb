# frozen_string_literal: true

module Allure
  module Fit
    # The byte stream is not a decodable FIT file: bad header size, missing
    # `.FIT` signature, CRC mismatch, truncated record, a data message
    # referencing an undefined local message type, or an unknown base type.
    #
    # Every decoding failure must funnel through here. A malformed upload may
    # never surface as an ArgumentError from `unpack1`, an unbounded read, or
    # a NoMethodError on nil.
    class MalformedFitError < Error; end
  end
end
