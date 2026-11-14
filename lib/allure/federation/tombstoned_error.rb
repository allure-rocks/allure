# frozen_string_literal: true

module Allure
  module Federation
    # A deleted local actor or object remains distinguishable from an unknown
    # resource so remote implementations can stop delivery and purge their copy.
    TombstonedError = Class.new(Error)
  end
end
