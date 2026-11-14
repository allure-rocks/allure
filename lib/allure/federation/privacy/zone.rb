# frozen_string_literal: true

module Allure
  module Federation
    module Privacy
      # A database-free privacy-zone value passed to the filter.
      Zone = Data.define(:center, :radius_meters)
    end
  end
end
