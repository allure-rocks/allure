# frozen_string_literal: true

module Allure
  module Gpx
    # Base class for every error the parser and analyzer can raise. Callers
    # (the importer) rescue this hierarchy to produce localized validation
    # errors instead of a 500.
    class Error < StandardError; end
  end
end
