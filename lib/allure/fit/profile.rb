# frozen_string_literal: true

module Allure
  module Fit
    # A hand-curated subset of the FIT Global Profile, not a generated SDK
    # dump. Only the messages and fields Allure actually consumes are named;
    # every other message is skipped by its declared length, so an unknown
    # message can never desynchronise the stream.
    #
    # See PLAN_FIT.md section 3.5. Adding a field here is the whole cost of
    # consuming it: the decoder needs no other change.
    module Profile
      # Global message number => message name.
      MESSAGES = {
        0 => :file_id,
        18 => :session,
        19 => :lap,
        20 => :record,
        21 => :event,
        23 => :device_info
      }.freeze

      # Message name => { field definition number => field name }.
      FIELDS = {
        file_id: {
          0 => :type,
          1 => :manufacturer,
          2 => :product,
          3 => :serial_number,
          4 => :time_created,
          8 => :product_name
        },
        # The session numbering is offset by one from the lap numbering for
        # the power and elevation totals: 21 is `max_power` here and
        # `total_ascent` in a lap. Reading 21/22 as the session totals turned
        # a running-power maximum into an ascent (PLAN_ELEVATION.md §3bis).
        session: {
          5 => :sport,
          6 => :sub_sport,
          11 => :total_calories,
          15 => :max_speed,
          21 => :max_power,
          22 => :total_ascent,
          23 => :total_descent,
          125 => :enhanced_max_speed
        },
        record: {
          253 => :timestamp,
          0 => :position_lat,
          1 => :position_long,
          2 => :altitude,
          3 => :heart_rate,
          4 => :cadence,
          5 => :distance,
          6 => :speed,
          7 => :power,
          13 => :temperature,
          73 => :enhanced_speed,
          78 => :enhanced_altitude
        },
        # A `lap` marks where the device recorded a lap. Its totals describe
        # that lap, not cumulative activity totals. Times and speeds have a
        # scale of 1000; distance has a scale of 100.
        lap: {
          253 => :timestamp,
          254 => :message_index,
          7 => :total_elapsed_time,
          8 => :total_timer_time,
          9 => :total_distance,
          13 => :avg_speed,
          14 => :max_speed,
          15 => :avg_heart_rate,
          16 => :max_heart_rate,
          17 => :avg_cadence,
          19 => :avg_power,
          21 => :total_ascent,
          22 => :total_descent,
          24 => :lap_trigger,
          52 => :total_moving_time,
          110 => :enhanced_avg_speed,
          111 => :enhanced_max_speed
        },
        event: {
          253 => :timestamp,
          0 => :event,
          1 => :event_type
        },
        device_info: {
          2 => :manufacturer,
          27 => :product_name
        }
      }.freeze

      # `file_id.type`. Only :activity is importable as a workout.
      FILE_TYPES = {
        1 => :device,
        2 => :settings,
        3 => :sport,
        4 => :activity,
        5 => :workout,
        6 => :course,
        7 => :schedules,
        9 => :weight,
        10 => :totals,
        11 => :goals,
        14 => :blood_pressure,
        15 => :monitoring_a,
        20 => :activity_summary,
        28 => :monitoring_daily,
        32 => :monitoring_b,
        34 => :segment,
        35 => :segment_list,
        40 => :exd_configuration
      }.freeze

      SPORTS = {
        0 => :generic,
        1 => :running,
        2 => :cycling,
        3 => :transition,
        4 => :fitness_equipment,
        5 => :swimming,
        6 => :basketball,
        7 => :soccer,
        8 => :tennis,
        9 => :american_football,
        10 => :training,
        11 => :walking,
        12 => :cross_country_skiing,
        13 => :alpine_skiing,
        14 => :snowboarding,
        15 => :rowing,
        16 => :mountaineering,
        17 => :hiking,
        18 => :multisport,
        19 => :paddling,
        20 => :flying,
        21 => :e_biking,
        22 => :motorcycling,
        23 => :boating,
        24 => :driving,
        25 => :golf,
        26 => :hang_gliding,
        27 => :horseback_riding,
        28 => :hunting,
        29 => :fishing,
        30 => :inline_skating,
        31 => :rock_climbing,
        32 => :sailing,
        33 => :ice_skating,
        34 => :sky_diving,
        35 => :snowshoeing,
        36 => :snowmobiling,
        37 => :stand_up_paddleboarding,
        38 => :surfing,
        39 => :wakeboarding,
        40 => :water_skiing,
        41 => :kayaking,
        42 => :rafting,
        43 => :windsurfing,
        44 => :kitesurfing,
        45 => :tactical,
        46 => :jumpmaster,
        47 => :boxing,
        48 => :floor_climbing,
        49 => :baseball,
        53 => :diving,
        62 => :hiit,
        64 => :racket,
        65 => :wheelchair_push_walk,
        66 => :wheelchair_push_run,
        67 => :meditation,
        76 => :water_tubing,
        77 => :wakesurfing,
        82 => :snorkeling,
        254 => :all
      }.freeze

      SUB_SPORTS = {
        0 => :generic,
        1 => :treadmill,
        2 => :street,
        3 => :trail,
        4 => :track,
        5 => :spin,
        6 => :indoor_cycling,
        7 => :road,
        8 => :mountain,
        9 => :downhill,
        10 => :recumbent,
        11 => :cyclocross,
        12 => :hand_cycling,
        13 => :track_cycling,
        14 => :indoor_rowing,
        15 => :elliptical,
        16 => :stair_climbing,
        17 => :lap_swimming,
        18 => :open_water,
        19 => :flexibility_training,
        20 => :strength_training,
        21 => :warm_up,
        22 => :match,
        23 => :exercise,
        24 => :challenge,
        25 => :indoor_skiing,
        26 => :cardio_training,
        27 => :indoor_walking,
        28 => :e_bike_fitness,
        29 => :bmx,
        30 => :casual_walking,
        31 => :speed_walking,
        32 => :bike_to_run_transition,
        33 => :run_to_bike_transition,
        34 => :swim_to_bike_transition,
        35 => :atv,
        36 => :motocross,
        37 => :backcountry,
        38 => :resort,
        39 => :rc_drone,
        40 => :wingsuit,
        41 => :whitewater,
        42 => :skate_skiing,
        43 => :yoga,
        44 => :pilates,
        45 => :indoor_running,
        46 => :gravel_cycling,
        47 => :e_bike_mountain,
        48 => :commuting,
        49 => :mixed_surface,
        50 => :navigate,
        51 => :track_me,
        52 => :map,
        53 => :single_gas_diving,
        54 => :multi_gas_diving,
        55 => :gauge_diving,
        56 => :apnea_diving,
        57 => :apnea_hunting,
        58 => :virtual_activity,
        59 => :obstacle,
        62 => :breathing,
        65 => :sail_race,
        67 => :ultra,
        68 => :indoor_climbing,
        69 => :bouldering,
        70 => :hiit,
        254 => :all
      }.freeze

      EVENTS = { 0 => :timer }.freeze

      EVENT_TYPES = {
        0 => :start,
        1 => :stop,
        2 => :consecutive_depreciated,
        3 => :marker,
        4 => :stop_all,
        5 => :begin_depreciated,
        6 => :end_depreciated,
        7 => :end_all_depreciated,
        8 => :stop_disable,
        9 => :stop_disable_all
      }.freeze

      # `lap.lap_trigger`: how the device opened the lap. Stored on the lap as a
      # display string (PLAN_M3.md section 6.1).
      LAP_TRIGGERS = {
        0 => :manual,
        1 => :distance,
        2 => :time,
        3 => :location,
        4 => :activity,
        5 => :session
      }.freeze

      module_function

      def message_name(global_message_number) = MESSAGES[global_message_number]

      def field_name(message_name, field_definition_number)
        FIELDS.dig(message_name, field_definition_number)
      end

      def file_type(value) = FILE_TYPES[value]
      def sport(value) = SPORTS[value]
      def sub_sport(value) = SUB_SPORTS[value]
      def event(value) = EVENTS[value]
      def event_type(value) = EVENT_TYPES[value]
      def lap_trigger(value) = LAP_TRIGGERS[value]
    end
  end
end
