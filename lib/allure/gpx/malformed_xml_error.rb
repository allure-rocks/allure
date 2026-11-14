# frozen_string_literal: true

module Allure
  module Gpx
    # The XML itself could not be parsed (malformed markup, premature end of
    # data, or an unresolved entity reference such as an XXE attempt).
    class MalformedXmlError < Error; end
  end
end
