# frozen_string_literal: true

module Allure
  module Units
    METRES_PER_KILOMETRE = 1_000.0
    METRES_PER_MILE = 1_609.344
    METRES_PER_FOOT = 0.3048
    SECONDS_PER_HOUR = 3_600.0

    module_function

    def metres_to_kilometres(metres) = metres.to_f / METRES_PER_KILOMETRE
    def metres_to_miles(metres) = metres.to_f / METRES_PER_MILE
    def metres_to_feet(metres) = metres.to_f / METRES_PER_FOOT

    def metres_per_second_to_kilometres_per_hour(speed)
      speed.to_f * SECONDS_PER_HOUR / METRES_PER_KILOMETRE
    end

    def metres_per_second_to_miles_per_hour(speed)
      speed.to_f * SECONDS_PER_HOUR / METRES_PER_MILE
    end

    def celsius_to_fahrenheit(celsius) = celsius.to_f * 9.0 / 5.0 + 32.0
    def millimetres_to_inches(millimetres) = millimetres.to_f / 25.4

    def seconds_per_kilometre_to_seconds_per_mile(pace)
      pace.to_f * METRES_PER_MILE / METRES_PER_KILOMETRE
    end
  end
end
