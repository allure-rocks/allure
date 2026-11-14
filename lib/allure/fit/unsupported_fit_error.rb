# frozen_string_literal: true

module Allure
  module Fit
    # The file decodes correctly but is not an Activity file. Course,
    # workout, settings, monitoring, totals and segment files describe
    # something other than a recorded effort; importing one as a workout
    # would fabricate an activity that never happened.
    class UnsupportedFitError < Error; end
  end
end
