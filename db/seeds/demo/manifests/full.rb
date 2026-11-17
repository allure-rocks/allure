# frozen_string_literal: true

# The full development dataset: ten personas whose activities come from the
# optional FIT conformance corpus (script/fetch-fit-corpus), chosen so that
# every account lives somewhere coherent and repeats its own roads, and so that
# a few activities were recorded by several accounts at once — the same ride
# or run on different devices — which is what fills the shared leaderboards,
# the participations and the comment threads with real geometry.
#
# Workout keys are per account; a segment, a participation or a comment names
# the account and the key. Segment anchors are coordinates on the source
# workout, snapped to the nearest recorded points at seed time.
module DemoSeed
  module Manifests
    # The demo instance and the development seed re-date the whole dataset so
    # its most recent activity lands near the present (PLAN_DEMO.md §2). The
    # few delayed publications sit on recent activities, so some are still
    # waiting once the dataset is re-dated. Each anchor is the newest date
    # of its family in this manifest: the files anchor matches the newest
    # `Activity_YYYYMMDD` corpus filename, the manual anchor the newest typed
    # `started_at`. spec/seeds/demo_manifest_spec.rb keeps them honest, so a
    # newer recording added here must move its anchor in the same patch.
    DATE_ANCHORS = { files: Date.new(2026, 4, 19), manual: Date.new(2026, 10, 13) }.freeze

    FULL = {
      accounts: [
        {
          username: "marie",
          discoverable: "members",
          leaderboard_category: "women",
          weather_enrichment_enabled: true,
          profile_statistics_audience: "members",
          profile_records_audience: "members",
          email: "marie@demo.allure.rocks",
          display_name: "Marie Dufour",
          bio: "Trail et cyclisme dans les Alpes, depuis Meylan.",
          locale: "fr",
          theme: "dark",
          time_zone: "Europe/Paris",
          default_sports: { cycling: "cycling_road" },
          equipment: [
            { label: "Lapierre Xelius", type: "bike", description: "Vélo de route, groupe Ultegra." },
            { label: "Hoka Speedgoat", type: "shoes" },
            { label: "VAE de location", type: "bike", description: "Loué une semaine en Ligurie." }
          ],
          privacy_zones: [ { name: "Maison", latitude: 45.2103, longitude: 5.7827, radius_meters: 400 } ],
          built_in_profiles: {
            public: { settings: { "gpx" => true, "records" => true, "device" => true, "commute" => true } }
          },
          workouts: [
            { key: :cucheron, file: "Activity/2014/Activity_20140818_002_000_Cycling_Edge800_d093aca90a8ed1a12ce2e07e78e242c0.fit",
              title: "Grand Cucheron et col du Champet", description: "Grande boucle par le Grésivaudan, Le Moutaret, Bourget-en-Huile et la Maurienne.",
              equipment: [ "Lapierre Xelius" ], publish: :public },
            { key: :monteynard, file: "Activity/2014/Activity_20141018_002_000_Cycling_Edge800_888b2b2b6cd36a3b41b1b873f41c1de3.fit",
              title: "Tour du lac de Monteynard", description: "Par la Matheysine, retour par Vizille.", equipment: [ "Lapierre Xelius" ], publish: :public },
            { key: :alpe, file: "Activity/2015/Activity_20150710_002_000_Cycling_Edge810_6bf94530cf12d0d816c71377c1539d58.fit",
              title: "L'Alpe d'Huez depuis Meylan", description: "Aller-retour par la vallée de la Romanche, les 21 lacets au milieu.",
              notes: "Départ 6 h 30, 34 °C au retour.", equipment: [ "Lapierre Xelius" ], publish: :public },
            { key: :crans_ski, file: "Activity/2016/Activity_20160313_012_000_Cross-Country-Skiing_Fenix3_9853f90e07b0ebd84fe5034eba5e510c.fit",
              title: "Ski de fond à Crans-Montana", publish: { audience: :public, delay: "1_week" } },
            { key: :gresivaudan, file: "Activity/2016/Activity_20160418_002_000_Cycling_Edge810_c276b75b9c3da9d1bcaec2f2ab3c900e.fit",
              title: "Grésivaudan et balcons de Belledonne", equipment: [ "Lapierre Xelius" ], publish: :public },
            { key: :footing_meylan, file: "Activity/2017/Activity_20171008_001_000_Running_VivoActiveHr_0f729ebd9707d1236014b810096acc6a.fit",
              title: "Footing du dimanche", equipment: [ "Hoka Speedgoat" ] },
            { key: :uriage_2019, file: "Activity/2019/Activity_20190811_002_007_Cycling_Road_Edge1000_dfcd2a6df6f53ec8e34bcafa0125c8f0.fit",
              title: "Saint-Martin-d'Uriage par Venon", equipment: [ "Lapierre Xelius" ], publish: :public },
            { key: :uriage_2021_09_05, file: "Activity/2021/Activity_20210905_002_007_Cycling_Road_Edge1000_f9fab7ca5e3236539839cd8e795605d5.fit",
              title: "Uriage et retour par Vizille", description: "Première sortie avec le capteur de puissance.", equipment: [ "Lapierre Xelius" ], publish: :public },
            { key: :uriage_2021_09_22, file: "Activity/2021/Activity_20210922_002_007_Cycling_Road_Edge1000_87516ffa7e77cb9eefa561ff4dc93b79.fit",
              title: "Murianette – Revel, sortie du midi", equipment: [ "Lapierre Xelius" ], publish: :public },
            { key: :sancy_day1, file: "Activity/2023/Activity_20230610_017_003_Hiking_Trail_Suunto-Vertical_d149673ba8d0667bef7a9fb68d91925d.fit",
              title: "Puy de Sancy, jour 1", description: "Avec Sophie, depuis le Mont-Dore.", equipment: [ "Hoka Speedgoat" ] },
            { key: :sancy_day2, file: "Activity/2023/Activity_20230610_017_003_Hiking_Trail_Suunto-Vertical_3139dfeee3252b9c7d50729f13b51d04.fit",
              title: "Puy de Sancy, jour 2", equipment: [ "Hoka Speedgoat" ], publish: :followers },
            { key: :liguria, file: "Activity/2025/Activity_20250714_002_028_Cycling_E-Bike-Fitness_Edge840_049f1f9d95ab86bf61629a4ab4421645.fit",
              title: "Cairo Montenotte en VAE", description: "Vacances en Ligurie, vélo loué sur place.", equipment: [ "VAE de location" ], publish: :public },
            { key: :chamonix, file: "Activity/2025/Activity_20250801_001_003_Running_Trail_Fenix8_1bf2206b0ddeb253729862521470045e.fit",
              title: "Argentière – Lac Blanc", description: "Montée directe au lac, descente par les Chéserys.",
              equipment: [ "Hoka Speedgoat" ], publish: :public }
          ],
          # Typed in by hand (docs/dev/MANUAL-ENTRY.md): a gym session and a run
          # the watch missed. They count in the totals and the shoes' wear,
          # never in the records.
          manual_workouts: [
            { key: :gym_2026_10, sport: "strength_training", title: "Renforcement à la salle", started_at: "2026-10-13T18:30",
              duration: 3000, average_heart_rate: 112, max_heart_rate: 148, calories: 310,
              notes: "Gainage, squats, fentes." },
            { key: :footing_no_watch, sport: "running", title: "Footing, montre oubliée", started_at: "2026-10-04T08:15",
              duration: 2280, distance: 6_200, ascent: 45, equipment: [ "Hoka Speedgoat" ],
              description: "Le tour habituel du parc, estimé sur la carte." }
          ],
          segments: [
            { key: :alpe_climb, workout: :alpe, name: "Alpe d'Huez, premiers lacets", description: "Du pied à Huez, la partie la plus raide.",
              visibility: "public", start: [ 45.06194, 6.03334 ], end: [ 45.07486, 6.05227 ], publish: true },
            { key: :cucheron_climb, workout: :cucheron, name: "Le Moutaret – Bourget-en-Huile", visibility: "followers_only",
              start: [ 45.43904, 6.09516 ], end: [ 45.48338, 6.20506 ] },
            { key: :uriage_climb, workout: :uriage_2021_09_22, name: "Murianette – Revel par Venon", visibility: "public",
              start: [ 45.19161, 5.81599 ], end: [ 45.18570, 5.86857 ] },
            { key: :lac_blanc, workout: :chamonix, name: "Argentière – Lac Blanc", visibility: "private", sport: nil,
              start: [ 46.0040, 6.9474 ], end: [ 45.9969, 6.9868 ] }
          ]
        },
        {
          username: "paul",
          discoverable: "members",
          leaderboard_category: "men",
          email: "paul@demo.allure.rocks",
          display_name: "Paul Martin",
          bio: "Bike commuter in North Portland. Long rides on weekends, Zwift when it rains.",
          locale: "en",
          theme: "light",
          unit_system: "imperial",
          time_zone: "America/Los_Angeles",
          week_start: "sunday",
          equipment: [
            { label: "Surly Cross-Check", type: "bike", description: "Commuter, fenders and racks." },
            { label: "Cannondale SuperSix", type: "bike" },
            { label: "Wahoo KICKR", type: "bike_trainer" }
          ],
          privacy_zones: [ { name: "Home", latitude: 45.5928, longitude: -122.7226, radius_meters: 300 } ],
          # Rides from the door hide where the door is; a trip elsewhere goes
          # out through a profile without the mask.
          built_in_profiles: { public: { settings: { "mask_start" => true, "mask_finish" => false, "commute" => true } } },
          profiles: [ { name: "Away rides", settings: { "mask_start" => false, "mask_finish" => false, "device" => true } } ],
          workouts: [
            { key: :troutdale, file: "Activity/2017/Activity_20170320_002_000_Cycling_Edge200_dc161c910cbe4a865f87eb0f6817da17.fit",
              title: "Marine Drive to Troutdale", equipment: [ "Cannondale SuperSix" ], publish: :public },
            { key: :commute_out_0401, file: "Activity/2017/Activity_20170401_002_000_Cycling_Edge200_008241b67934befe414f04541f308157.fit",
              title: "Commute home", equipment: [ "Surly Cross-Check" ], commute: true },
            { key: :commute_in_0403, file: "Activity/2017/Activity_20170403_002_000_Cycling_Edge200_2443d90a480ac01f79f59e3701325712.fit",
              title: "Commute to downtown", equipment: [ "Surly Cross-Check" ], commute: true },
            { key: :commute_out_0403, file: "Activity/2017/Activity_20170403_002_000_Cycling_Edge200_dc7ab6cc385f48b956d219be124bf301.fit",
              title: "Commute home via the Eastbank", equipment: [ "Surly Cross-Check" ], commute: true },
            { key: :commute_in_0404, file: "Activity/2017/Activity_20170404_002_000_Cycling_Edge200_9e6f47b6385e46fa8382d8aa14a8e58a.fit",
              title: "Commute to downtown, dry roads", equipment: [ "Surly Cross-Check" ], commute: true, publish: :public },
            { key: :commute_out_0405, file: "Activity/2017/Activity_20170405_002_000_Cycling_Edge200_df41b9c7e6ef3c908de1a6c2e342e672.fit",
              title: "Commute home, headwind", equipment: [ "Surly Cross-Check" ], commute: true },
            { key: :commute_in_0421, file: "Activity/2017/Activity_20170421_002_000_Cycling_Edge200_36d92517b90926b9a0bd4d7828ec7268.fit",
              title: "Commute to downtown, short way", equipment: [ "Surly Cross-Check" ], commute: true },
            { key: :commute_out_0505, file: "Activity/2017/Activity_20170505_002_000_Cycling_Edge200_956d04d3d853c9fa07df9d54528e91b1.fit",
              title: "Commute home, Friday", equipment: [ "Surly Cross-Check" ], commute: true },
            { key: :commute_in_0508, file: "Activity/2017/Activity_20170508_002_000_Cycling_Edge200_354cf64a04c46ad2cdd50405603f9bcc.fit",
              title: "Commute to downtown via Willamette Blvd", equipment: [ "Surly Cross-Check" ], commute: true, publish: :public },
            { key: :commute_out_0509, file: "Activity/2017/Activity_20170509_002_000_Cycling_Edge200_ae871fe3074eef4655c53413ecdd7b53.fit",
              title: "Commute home, sunset", equipment: [ "Surly Cross-Check" ], commute: true },
            { key: :commute_out_0510, file: "Activity/2017/Activity_20170510_002_000_Cycling_Edge200_eafa9aa1207b682688929181a9fd223d.fit",
              title: "Commute home, late", equipment: [ "Surly Cross-Check" ], commute: true },
            { key: :commute_in_0510, file: "Activity/2017/Activity_20170510_002_000_Cycling_Edge200_0e5e0bffddcaf51e88e6714d5efe64b6.fit",
              title: "Commute to downtown, fast", equipment: [ "Surly Cross-Check" ], commute: true },
            { key: :pacific_city, file: "Activity/2017/Activity_20170520_002_000_Cycling_Edge200_48ec8956fbe7dea6563dae879af82dd1.fit",
              title: "Portland to Pacific City", description: "One way to the coast through the Yamhill valley; the car came back.",
              equipment: [ "Cannondale SuperSix" ], publish: { profile: "Away rides" } },
            { key: :zwift_2025_02, file: "Activity/2025/Activity_20250227_002_058_Cycling_Virtual-Activity_Zwift_bbe30b5b047a57e0585d256cf4c4052c.fit",
              title: "Zwift: Watopia endurance", equipment: [ "Wahoo KICKR" ], publish: { profile: "Away rides" } },
            { key: :zwift_2025_11, file: "Activity/2025/Activity_20251110_002_058_Cycling_Virtual-Activity_Zwift_ee13dc97dec3c9c0668d85f9646f58cf.fit",
              title: "Zwift: tempo intervals", equipment: [ "Wahoo KICKR" ] },
            { key: :zwift_2026_01, file: "Activity/2026/Activity_20260106_002_058_Cycling_Virtual-Activity_Zwift_170440296b5634279cb0aaf47a031e70.fit",
              title: "Zwift: first ride of the year", equipment: [ "Wahoo KICKR" ], publish: { profile: "Away rides" } }
          ],
          manual_workouts: [
            { key: :spin_class, sport: "fitness", title: "Spin class at the gym", started_at: "2026-02-10T18:00",
              duration: 2700, average_heart_rate: 141, max_heart_rate: 172, calories: 520 },
            { key: :commute_no_gps, sport: "cycling", title: "Commute home, phone dead", started_at: "2017-05-12T17:40",
              duration: 1980, moving_time: 1740, distance: 9_650, ascent: 30, equipment: [ "Surly Cross-Check" ], commute: true }
          ],
          segments: [
            { key: :willamette, workout: :commute_in_0508, name: "Willamette Blvd: Portsmouth to Greeley", visibility: "private",
              start: [ 45.58208, -122.72443 ], end: [ 45.54581, -122.68177 ] },
            { key: :broadway, workout: :commute_out_0505, name: "Broadway Bridge to Interstate", visibility: "private",
              start: [ 45.53148, -122.67470 ], end: [ 45.54516, -122.67775 ] },
            { key: :commute_in_route, workout: :commute_in_0508, name: "Commute to downtown", kind: "route" },
            { key: :commute_out_route, workout: :commute_out_0505, name: "Commute home", kind: "route" }
          ]
        },
        {
          username: "sophie",
          discoverable: "members",
          leaderboard_category: "women",
          profile_statistics_audience: "followers",
          profile_records_audience: "followers",
          email: "sophie@demo.allure.rocks",
          display_name: "Sophie Weber",
          bio: "Coureuse depuis 2011, entre Strassen et Metz.",
          locale: "fr",
          theme: "light",
          time_zone: "Europe/Luxembourg",
          equipment: [
            { label: "Asics Kayano (2011)", type: "shoes", description: "La première paire sérieuse." },
            { label: "Saucony Kinvara", type: "shoes" },
            { label: "Skis Rossignol", type: "skis" }
          ],
          privacy_zones: [ { name: "Appartement de Metz", latitude: 49.1159, longitude: 6.1790, radius_meters: 250 } ],
          profiles: [
            { name: "Sans itinéraire", settings: { "route" => false, "route_image" => false, "gpx" => false, "metrics" => %w[distance duration moving_time average_pace] } }
          ],
          workouts: [
            { key: :strassen_2011, file: "Activity/2011/Activity_20110912_001_Running_Fr110_26dafb6d40695b874d393df131f28ec4.fit",
              title: "Bambësch par le Reckenthal", equipment: [ "Asics Kayano (2011)" ], publish: :public },
            { key: :mersch_2012, file: "Activity/2012/Activity_20120118_001_Running_Fr110_5b6d8ce345e09bd305e821ee27b5aeca.fit",
              title: "Piste cyclable de l'Alzette", description: "Depuis Berschbach, aller-retour le long de la rivière.", equipment: [ "Asics Kayano (2011)" ], publish: :public },
            { key: :strassen_2012_02, file: "Activity/2012/Activity_20120201_001_Running_Fr110_3abe8ba348f16ff83127c9d820b56b81.fit",
              title: "10 km dans le froid", equipment: [ "Asics Kayano (2011)" ], publish: :public },
            { key: :strassen_2012_10, file: "Activity/2012/Activity_20121020_001_Running_Fr110_e25e42d536128ddb761dbb903d7cfc43.fit",
              title: "Côte du Reckenthal, test", equipment: [ "Asics Kayano (2011)" ], publish: :public },
            { key: :strassen_2013, file: "Activity/2013/Activity_20130314_001_Running_Fr110_6ba1230585e688ec7725e7780d625bec.fit",
              title: "Boucle du Bambësch", equipment: [ "Asics Kayano (2011)" ], publish: :public },
            { key: :metz_2017_03, file: "Activity/2017/Activity_20170305_001_000_Running_Fr920xt_714c2b8198e060c6ebf2d06c43cc74bc.fit",
              title: "Reprise, Sablon", equipment: [ "Saucony Kinvara" ], publish: { profile: "Sans itinéraire" } },
            { key: :gerardmer_ski, file: "Activity/2017/Activity_20170312_013_000_Alpine-Skiing_Fr920xt_ee502bf3a06c4f52e2664d7e3ddddb65.fit",
              title: "Journée de ski à Gérardmer", equipment: [ "Skis Rossignol" ], publish: :public },
            { key: :metz_2017_04, file: "Activity/2017/Activity_20170423_001_000_Running_Fr920xt_ebcaa5115e3fd42a591fd6aaa30cc40a.fit",
              title: "Bords de Seille et Pont de Magny", equipment: [ "Saucony Kinvara" ], publish: { profile: "Sans itinéraire" } },
            { key: :metz_2017_06, file: "Activity/2017/Activity_20170602_001_000_Running_Fr920xt_ce4b216acb4eff5c2acc60ee0f073efd.fit",
              title: "Tour de la Nouvelle Ville", equipment: [ "Saucony Kinvara" ], publish: { profile: "Sans itinéraire" } },
            { key: :metz_2017_07, file: "Activity/2017/Activity_20170723_001_000_Running_Fr920xt_4effc9dcc1101c3b85a4f5046a34f634.fit",
              title: "Sortie du dimanche matin", equipment: [ "Saucony Kinvara" ] },
            { key: :metz_2018, file: "Activity/2018/Activity_20180405_001_000_Running_Fr935_bed944d53d14e031cc818d5ccf2a7ce1.fit",
              title: "Première sortie avec la 935", equipment: [ "Saucony Kinvara" ], publish: { profile: "Sans itinéraire" } },
            { key: :strassen_2019_08, file: "Activity/2019/Activity_20190804_001_000_Running_Fr935_14d1042ae99f3d3adacaabccbe976488.fit",
              title: "Reckenthal, retour à Strassen", equipment: [ "Saucony Kinvara" ], publish: :public },
            { key: :strassen_2019_09, file: "Activity/2019/Activity_20190907_001_000_Running_Fr935_234df8b827aa2aec5eeca04e6c19db1a.fit",
              title: "10 km du Bambësch", description: "Record personnel sur la boucle.", equipment: [ "Saucony Kinvara" ], publish: :public }
          ],
          manual_workouts: [
            { key: :treadmill_2019, sport: "running_virtual", title: "Tapis à la salle", started_at: "2019-11-20T19:00",
              duration: 2400, distance: 7_000, average_heart_rate: 152, equipment: [ "Saucony Kinvara" ] }
          ],
          segments: [
            { key: :reckenthal, workout: :strassen_2012_10, name: "Côte du Reckenthal", description: "La montée de Strassen vers le Bambësch.",
              visibility: "public", start: [ 49.62412, 6.09097 ], end: [ 49.62852, 6.09125 ] },
            { key: :seille, workout: :metz_2017_04, name: "Bords de Seille", visibility: "private",
              start: [ 49.10051, 6.18756 ], end: [ 49.08882, 6.18180 ] },
            { key: :alzette_route, workout: :mersch_2012, name: "Piste cyclable de l'Alzette", kind: "route" }
          ]
        },
        {
          username: "tom",
          discoverable: "members",
          leaderboard_category: "men",
          weather_enrichment_enabled: true,
          profile_statistics_audience: "members",
          profile_records_audience: "members",
          email: "tom@demo.allure.rocks",
          display_name: "Tom de Vries",
          bio: "Amsterdam Zuid. Running, road bike, and a training camp in Mallorca every winter.",
          locale: "en",
          theme: "dark",
          time_zone: "Europe/Amsterdam",
          default_sports: { cycling: "cycling_road" },
          equipment: [
            { label: "Canyon Ultimate", type: "bike" },
            { label: "Trek Fuel EX", type: "bike", description: "Mountain bike." },
            { label: "Nike Pegasus 40", type: "shoes" }
          ],
          privacy_zones: [ { name: "Home", latitude: 52.3511, longitude: 4.8523, radius_meters: 250 } ],
          built_in_profiles: { public: { settings: { "device" => true, "records" => true } } },
          workouts: [
            { key: :new_year_run, file: "Activity/2018/Activity_20180101_001_000_Running_Fr935_1741e101eec8e8d25a62859c8a9859be.fit",
              title: "New Year's run around Vondelpark", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :saturday_run_2019, file: "Activity/2019/Activity_20190420_001_000_Running_Fr945_940084500c6ab106aa4cf820b8906653.fit",
              title: "Saturday run with Eva", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :waterland, file: "Activity/2020/Activity_20200831_002_000_Cycling_Fr745_a1842ed65e41131c973fefe922ba485f.fit",
              title: "Waterland loop", description: "Durgerdam, Uitdam, Holysloot and back over the dike.", equipment: [ "Canyon Ultimate" ], publish: :public },
            { key: :posbank, file: "Activity/2020/Activity_20201023_002_008_Cycling_Mountain_Suunto-Spartan-Sport-Wrist-HR-Baro_405f58c2aced451bf4bfa97d81f7b7c0.fit",
              title: "Posbank trails", equipment: [ "Trek Fuel EX" ], publish: :followers },
            { key: :haarlemmermeer, file: "Activity/2020/Activity_20201202_002_000_Cycling_Fr745_a739bb6b29a53ec9e323aaf98dfc2087.fit",
              title: "Haarlemmermeer ring", equipment: [ "Canyon Ultimate" ], publish: :public },
            { key: :amstelveen_run, file: "Activity/2022/Activity_20221029_001_000_Running_Fr955_c28ee6ab8b36a13278f32c2a8ba509e2.fit",
              title: "Amstelveen 10k", equipment: [ "Nike Pegasus 40" ] },
            { key: :long_run_30k, file: "Activity/2023/Activity_20231117_001_000_Running_EpixGen2Pro47_c75d9bf2e85e2046e207c1f8f6058faa.fit",
              title: "30 km through the Amsterdamse Bos", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :jan_wilsbrug_run, file: "Activity/2024/Activity_20240415_001_000_Running_Fr965_5c7e5c3fa1f67bbcbe4b3516aa43e629.fit",
              title: "Lunch run to the Jan Wilsbrug", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :west_coast, file: "Activity/2024/Activity_20241127_002_007_Cycling_Road_Edge1050_bb90ba7330261cac638341effa7dbc57.fit",
              title: "Andratx, Estellencs, Banyalbufar", description: "The west coast on the Ma-10 with Joan and Inès.", equipment: [ "Canyon Ultimate" ], publish: :public },
            { key: :sa_creu_2025, file: "Activity/2025/Activity_20250107_002_007_Cycling_Road_Edge1050_d82f9b094046a95b1f74489a24e0aeff.fit",
              title: "Coll de sa Creu loop", equipment: [ "Canyon Ultimate" ], publish: :public },
            { key: :easy_8k, file: "Activity/2025/Activity_20250113_001_000_Running_Fr965_26c406c6f96b1d9dfe7b5a6b75fc9fc0.fit",
              title: "Easy 8k along the bay", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :galatzo_hike, file: "Activity/2025/Activity_20250115_017_000_Hiking_Fenix8_71be2c07d18cb10e07e222da86be489b.fit",
              title: "Galatzó traverse from Peguera", description: "A full day: Peguera, Es Capdellà, the Galatzó summit and home along the coast.",
              publish: :public },
            { key: :spring_hills_ride, file: "Activity/2025/Activity_20250507_002_007_Cycling_Road_Edge1050_6d5a59d08092c589c211253286283219.fit",
              title: "Spring ride over the hills", description: "Out with Joan: the coast road, the long climb, the descent to the bay.",
              equipment: [ "Canyon Ultimate" ], publish: :public },
            { key: :hilly_run_with_joan, file: "Activity/2025/Activity_20250509_001_000_Running_Fenix8_66d0c9d4e357d20e1856c6a6ef9c5ccb.fit",
              title: "Hilly run with Joan", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :ultra, file: "Activity/2025/Activity_20250929_001_003_Running_Trail_Fenix8Pro_43461e435442ca4b0379fbbe4e95bd58.fit",
              title: "Tramuntana ultra, 70 km", description: "Galatzó, Puigpunyent and the long way back. Joan paced the climbs.",
              notes: "Nutrition: gels every 40 min, salt at the aid stations. Quads gone at km 55.", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :portals_vells_long_run, file: "Activity/2025/Activity_20251013_001_000_Running_Fenix8Pro_f2355877f45f8df2be2b5cc0fec89b9d.fit",
              title: "Sunday long run to Portals Vells", description: "The ridge traverse above El Toro, two hours on the trails with Inès and Joan.",
              equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :magaluf_evening_run, file: "Activity/2025/Activity_20251029_001_000_Running_Fenix8Pro_da52e7f462ce985ca761d91f6fabba25.fit",
              title: "Evening run to Magaluf", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :cala_vinyes_long_run, file: "Activity/2025/Activity_20251101_001_000_Running_Fenix8Pro_300dc3eea958c80a481a6f93be81a7f1.fit",
              title: "Long run along the coast", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :quick_evening_run, file: "Activity/2025/Activity_20251104_001_000_Running_Fenix8Pro_e6e0fd16ae73bca345a9fd546b2d80ed.fit",
              title: "Quick evening run", equipment: [ "Nike Pegasus 40" ] },
            { key: :blanes_hills_run, file: "Activity/2026/Activity_20260215_001_000_Running_Forerunner-970_f1bf55a30e94b2cc1a20fb8a247508cb.fit",
              title: "Hills above Costa d'en Blanes", description: "Almost 400 metres of climbing before breakfast.",
              equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :galatzo_trail, file: "Activity/2026/Activity_20260225_001_003_Running_Trail_Fenix8Pro_7f794801cb7af3858ef29ed82d6f74c4.fit",
              title: "Galatzó trail from Es Capdellà", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :florida_beach_run, file: "Activity/2026/Activity_20260407_001_000_Running_Fenix8Pro_d6d4598ac7eae3695679dbac863089dd.fit",
              title: "Daytona midday run", notes: "Spring trip to Florida: flat, straight and hot along the water.",
              equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :florida_night_run, file: "Activity/2026/Activity_20260410_001_000_Running_Fenix8Pro_d2044c3157a87ddfe6ed950f8752b61d.fit",
              title: "Daytona night run", equipment: [ "Nike Pegasus 40" ], publish: :public },
            { key: :florida_evening_run, file: "Activity/2026/Activity_20260410_001_000_Running_Fenix8Pro_e79cd9ba7423c7f00caeb5faef1bda80.fit",
              title: "Daytona double, evening", equipment: [ "Nike Pegasus 40" ] },
            { key: :sa_creu_2026, file: "Activity/2026/Activity_20260414_002_000_Cycling_Fenix8Pro_8dccf986c421177c556dc93201d8bf72.fit",
              title: "Coll de sa Creu with Joan and Inès", equipment: [ "Canyon Ultimate" ], publish: [ :public, :followers ] },
            { key: :palmanova_half, file: "Activity/2026/Activity_20260418_001_000_Running_Fenix8Pro_4af19ad0869209574497ef34af1638a3.fit",
              title: "Palmanova half marathon", equipment: [ "Nike Pegasus 40" ], publish: { audience: :public, delay: "1_week" } }
          ],
          segments: [
            { key: :sa_creu, workout: :sa_creu_2025, name: "Coll de sa Creu from Calvià", description: "From the camí de Son Pillo to the top of the Ma-1016.",
              visibility: "public", start: [ 39.54547, 2.49700 ], end: [ 39.58725, 2.55432 ], publish: true },
            { key: :jan_wilsbrug, workout: :jan_wilsbrug_run, name: "Jachthavenweg to Jan Wilsbrug", visibility: "public",
              start: [ 52.33440, 4.85469 ], end: [ 52.34447, 4.85112 ] },
            { key: :el_toro_ridge, workout: :portals_vells_long_run, name: "El Toro to Portals Vells ridge",
              description: "The traverse of the coastal range west of Santa Ponça, any sport.",
              visibility: "public", sport: nil, tolerance: 40, start: [ 39.48134, 2.48457 ], end: [ 39.46818, 2.50156 ] },
            { key: :cala_vinyes_bay, workout: :magaluf_evening_run, name: "Cala Vinyes to Magaluf",
              description: "The flat seafront leg every recovery run takes.",
              visibility: "public", tolerance: 40, start: [ 39.49057, 2.51037 ], end: [ 39.50480, 2.52511 ] },
            { key: :blanes_climb, workout: :blanes_hills_run, name: "Costa d'en Blanes climb",
              description: "From the coast road to the ridge, almost 400 m of climbing.",
              visibility: "public", sport: nil, tolerance: 30, start: [ 39.53000, 2.54742 ], end: [ 39.54665, 2.53644 ] },
            { key: :palmanova_coast, workout: :palmanova_half, name: "Palmanova coastal leg",
              description: "The out-and-back leg of the half marathon course, along the water.",
              visibility: "public", start: [ 39.49874, 2.51786 ], end: [ 39.49844, 2.49942 ] },
            { key: :waterland_route, workout: :waterland, name: "Waterland loop", kind: "route" }
          ]
        },
        {
          username: "eva",
          discoverable: "members",
          leaderboard_category: "women",
          email: "eva@demo.allure.rocks",
          display_name: "Eva Jansen",
          bio: "Runs with Tom, swims on Mondays, rows when it rains.",
          locale: "en",
          theme: "light",
          time_zone: "Europe/Amsterdam",
          default_sports: { cycling: "cycling_road" },
          equipment: [
            { label: "Hoka Clifton", type: "shoes" },
            { label: "Specialized Allez", type: "bike" }
          ],
          workouts: [
            { key: :new_year_run, file: "Activity/2018/Activity_20180101_001_Running_Suunto-Spartan-Trainer-Wrist-HR_60d036934579b3fe0ac7cd3b93c9571c.fit",
              title: "New Year's run", equipment: [ "Hoka Clifton" ], publish: :public },
            { key: :saturday_run_2019, file: "Activity/2019/Activity_20190420_001_Running_Suunto-Spartan-Trainer-Wrist-HR_5844248ee57d93dec9a79c76de80c29a.fit",
              title: "Saturday run with Tom", equipment: [ "Hoka Clifton" ], publish: :public },
            { key: :waterland, file: "Activity/2020/Activity_20200831_002_Cycling_COROS-PACE-2_543790754c5cd330aa683e39c3cee02f.fit",
              title: "Waterland with Tom", equipment: [ "Specialized Allez" ], publish: :public },
            { key: :rowing, file: "Activity/2020/Activity_20201124_004_014_Fitness-Equipment_Indoor-Rowing_Waterrower_f19e60bd6d79e8d3fb6d2ba8ae804354.fit",
              title: "Rower: 10 km steady", publish: :public },
            { key: :haarlemmermeer, file: "Activity/2020/Activity_20201202_002_000_Cycling_ELEMNT-RIVAL_cedfa2481ad9a778e99d60ec348c3ee8.fit",
              title: "Haarlemmermeer ring", equipment: [ "Specialized Allez" ], publish: :public },
            { key: :amstelveen_run, file: "Activity/2022/Activity_20221029_001_Running_COROS-VERTIX-2_c2d09c15f1314b043dfeeb0544360937.fit",
              title: "Amstelveen 10k", equipment: [ "Hoka Clifton" ], publish: :public },
            { key: :pool, file: "Activity/2022/Activity_20221031_005_Swimming_COROS-Wearables_71d89d7c5b9b14752bc1b754b77e3ed3.fit",
              title: "Monday swim" },
            { key: :long_run_30k, file: "Activity/2023/Activity_20231117_001_Running_COROS-PACE-3_badb78c49b7aef7b5e112f28da83604c.fit",
              title: "30 km, Amsterdamse Bos", equipment: [ "Hoka Clifton" ], publish: :public },
            { key: :jan_wilsbrug_run, file: "Activity/2024/Activity_20240415_001_Running_COROS-Wearables_d06d565ab2b9f3b7d63d49d66e726df8.fit",
              title: "Lunch run with Tom", equipment: [ "Hoka Clifton" ], publish: :public },
            { key: :sa_creu_2026, file: "Activity/2026/Activity_20260414_002_000_Cycling_InstinctE45mm_8b31ae5ee9b1430735855eb6009d33ef.fit",
              title: "Sa Creu with the Mallorca crowd", description: "April visit: one big climb with Tom, Joan and Inès.",
              equipment: [ "Specialized Allez" ], publish: :public }
          ],
          segments: [
            { key: :durgerdam, workout: :waterland, name: "Durgerdammerdijk to Holysloot", visibility: "public",
              start: [ 52.37763, 4.99089 ], end: [ 52.39988, 5.03023 ] }
          ]
        },
        {
          username: "joan",
          discoverable: "members",
          weather_enrichment_enabled: true,
          email: "joan@demo.allure.rocks",
          display_name: "Joan Riera",
          bio: "Sol de Mallorca. Road, trail and the sea when it is flat.",
          locale: "en",
          theme: "dark",
          time_zone: "Europe/Madrid",
          default_sports: { cycling: "cycling_road" },
          equipment: [
            { label: "Orbea Orca", type: "bike" },
            { label: "Salomon Speedcross", type: "shoes" }
          ],
          privacy_zones: [ { name: "Casa", latitude: 39.4832, longitude: 2.5215, radius_meters: 300 } ],
          workouts: [
            { key: :west_coast, file: "Activity/2024/Activity_20241127_002_007_Cycling_Road_COROS-DURA_365a0d9fc7c2e70e10471e7a09098e1d.fit",
              title: "West coast with Tom and Inès", equipment: [ "Orbea Orca" ], publish: :public },
            { key: :sa_creu_2025, file: "Activity/2025/Activity_20250107_002_007_Cycling_Road_COROS-DURA_467d58a64c6a2500f36e542884627396.fit",
              title: "Coll de sa Creu, January camp", equipment: [ "Orbea Orca" ], publish: :public },
            { key: :easy_8k, file: "Activity/2025/Activity_20250113_001_000_Running_Instinct3Amoled50mm_d76ca870490e83f438448e1d6810cb6d.fit",
              title: "Easy 8k with the Dutch", equipment: [ "Salomon Speedcross" ], publish: :public },
            { key: :galatzo_hike, file: "Activity/2025/Activity_20250115_017_000_Hiking_Instinct2x_9c94bba77d0bcc694d4def02d5cef3f2.fit",
              title: "Galatzó traverse", publish: :public },
            { key: :spring_hills_ride, file: "Activity/2025/Activity_20250507_002_007_Cycling_Road_COROS-DURA_fea73e2bdc368f2f57c6c6c14e3cd457.fit",
              title: "Spring ride over the hills", description: "With Tom, before the summer heat comes back.", equipment: [ "Orbea Orca" ], publish: :public },
            { key: :swim_may, file: "Activity/2025/Activity_20250508_005_018_Swimming_Open-Water_Suunto_4f43d361e62724782b341b5925c2cd11.fit",
              title: "Portals Vells, first swim of the year" },
            { key: :trail_9k, file: "Activity/2025/Activity_20250509_001_003_Running_Trail_Suunto_169af3e8954e1614b4583c5c143d13e1.fit",
              title: "Trail above Santa Ponça", equipment: [ "Salomon Speedcross" ], publish: :public },
            { key: :ultra, file: "Activity/2025/Activity_20250929_001_003_Running_Trail_COROS-Wearables_09bd6787a65a68ae5206775db80cc762.fit",
              title: "Tramuntana ultra", equipment: [ "Salomon Speedcross" ] },
            { key: :portals_vells_trail, file: "Activity/2025/Activity_20251013_001_003_Running_Trail_COROS-Wearables_41a1dfca3da529ca4b61d27a56c84a23.fit",
              title: "Trail to Portals Vells with Tom and Inès", equipment: [ "Salomon Speedcross" ], publish: :public },
            { key: :run_10k_oct, file: "Activity/2025/Activity_20251029_001_Running_COROS-Wearables_569cc45712b30b80db816b2b30609e16.fit",
              title: "10k before work", equipment: [ "Salomon Speedcross" ], publish: :public },
            { key: :cala_vinyes_run, file: "Activity/2025/Activity_20251101_001_Running_COROS-Wearables_f2c5046eff0d854913fc72046d3e26e2.fit",
              title: "Coastal run with Tom", equipment: [ "Salomon Speedcross" ], publish: :public },
            { key: :swim_nov, file: "Activity/2025/Activity_20251104_005_018_Swimming_Open-Water_COROS-Wearables_a2457db301912e770ec7c01f1036a1b5.fit",
              title: "November dip at Portals Vells" },
            { key: :blanes_hills_run, file: "Activity/2026/Activity_20260215_001_002_Running_Street_Amazfit-T-Rex-Ultra-2_3129e947a3f5a9b67e11ccf48fc7911d.fit",
              title: "Long hilly run with Tom", equipment: [ "Salomon Speedcross" ], publish: :public },
            { key: :galatzo_trail, file: "Activity/2026/Activity_20260225_001_003_Running_Trail_Amazfit-T-Rex-Ultra-2_08831bf7646a897245c4bf6763ab69c5.fit",
              title: "Galatzó trail", equipment: [ "Salomon Speedcross" ], publish: :public },
            { key: :sa_creu_2026, file: "Activity/2026/Activity_20260414_002_048_Cycling_Commuting_Edge550_69289d34ff391b8da766d7af46e5f01e.fit",
              title: "Sa Creu on the new Edge", description: "The head unit called it a commute; it was not.", equipment: [ "Orbea Orca" ],
              commute: false, publish: { audience: :public, delay: "1_week" } },
            { key: :palmanova_half, file: "Activity/2026/Activity_20260418_001_Running_COROS-PACE-Pro_fcfb1ca4be897406e005477b6eeafca5.fit",
              title: "Palmanova half marathon", equipment: [ "Salomon Speedcross" ], publish: :public }
          ],
          segments: [
            # A mountain path under cliffs and trees: the wider corridor lets
            # the trail recordings join the hikes on the same board.
            { key: :galatzo, workout: :galatzo_hike, name: "Pujada al Galatzó", description: "From the camí de ses Sínies to the coma d'en Vidal, any sport.",
              visibility: "public", sport: nil, tolerance: 40, start: [ 39.60839, 2.46920 ], end: [ 39.63338, 2.45978 ], publish: true }
          ]
        },
        {
          username: "ines",
          discoverable: "members",
          leaderboard_category: "women",
          weather_enrichment_enabled: true,
          email: "ines@demo.allure.rocks",
          display_name: "Inès Morel",
          bio: "Française installée à Santa Ponça. Course à pied, vélo avec les voisins.",
          locale: "fr",
          theme: "light",
          time_zone: "Europe/Madrid",
          default_sports: { cycling: "cycling_road" },
          equipment: [
            { label: "BMC Roadmachine", type: "bike" },
            { label: "Brooks Ghost", type: "shoes" }
          ],
          privacy_zones: [ { name: "Maison", latitude: 39.4832, longitude: 2.5215, radius_meters: 300 } ],
          built_in_profiles: { followers: { delay: "1_day" } },
          workouts: [
            { key: :west_coast, file: "Activity/2024/Activity_20241127_002_000_Cycling_ELEMNT-ACE_dacdfa20f446bfd75ebb99196733658f.fit",
              title: "Côte ouest : Andratx, Estellencs, Banyalbufar", equipment: [ "BMC Roadmachine" ], publish: :public },
            { key: :sa_creu_2025, file: "Activity/2025/Activity_20250107_002_000_Cycling_Fenix8_326f443ae8b152b3538324bc8207ab88.fit",
              title: "Coll de sa Creu avec Tom et Joan", equipment: [ "BMC Roadmachine" ], publish: :public },
            { key: :easy_8k, file: "Activity/2025/Activity_20250113_001_000_Running_Fenix8_79e7985a85cdccef74f01e682856c530.fit",
              title: "Footing Santa Ponça", equipment: [ "Brooks Ghost" ], publish: :public },
            { key: :galatzo_hike, file: "Activity/2025/Activity_20250115_017_000_Hiking_Instinct3Solar50mm_39012ebcbc0b670cee8538babd457cb0.fit",
              title: "Traversée du Galatzó", publish: :public },
            { key: :run_15k, file: "Activity/2025/Activity_20250123_001_000_Running_Watch7,5_22d94b8a706d057ae3f63966a845f7fb.fit",
              title: "15 km vers Palmanova", equipment: [ "Brooks Ghost" ], publish: :followers },
            { key: :beach_run, file: "Activity/2025/Activity_20250508_001_000_Running_Fenix8_f31012317f90c41c54f631a5fd482a01.fit",
              title: "Footing jusqu'à la plage", equipment: [ "Brooks Ghost" ], publish: :public },
            { key: :ultra, file: "Activity/2025/Activity_20250929_001_000_Running_Watch7,12_fa51b4323bc0873734865363eabd336a.fit",
              title: "Ultra de la Tramuntana", description: "Fini. Debout. C'est tout ce qui compte.", equipment: [ "Brooks Ghost" ], publish: :public },
            { key: :portals_vells_trail, file: "Activity/2025/Activity_20251013_001_000_Running_Watch7,12_5d6e24b0e8f4eb0da9fad6a550867d67.fit",
              title: "Traversée du Portals Vells avec Tom et Joan", equipment: [ "Brooks Ghost" ], publish: :public },
            { key: :magaluf_run, file: "Activity/2025/Activity_20251029_001_000_Running_Watch7,12_5bbca7c7212fe2f7b39318641d79fda2.fit",
              title: "Jusqu'à Magaluf et retour", equipment: [ "Brooks Ghost" ], publish: :public },
            { key: :autumn_swim, file: "Activity/2025/Activity_20251104_005_018_Swimming_Open-Water_Watch7,12_eaf31b634e479c985c65ac26f73eb62f.fit",
              title: "Baignade d'automne", publish: :public },
            { key: :galatzo_trail, file: "Activity/2026/Activity_20260225_001_000_Running_iPhone17,1_b83974de63b0e3fc1848d2c2fac1816f.fit",
              title: "Trail du Galatzó", equipment: [ "Brooks Ghost" ], publish: :public },
            { key: :sa_creu_2026, file: "Activity/2026/Activity_20260414_002_007_Cycling_Road_Polar-Street-X_b66ac9dc4445426008f74b93097b8666.fit",
              title: "Sa Creu, sortie du mardi", equipment: [ "BMC Roadmachine" ], publish: :public },
            { key: :palmanova_half, file: "Activity/2026/Activity_20260418_001_002_Running_Street_Polar-Street-X_2018449d3a2a0c98e35e013d5bf67844.fit",
              title: "Semi de Palmanova", equipment: [ "Brooks Ghost" ], publish: { audience: :public, delay: "3_days" } }
          ],
          segments: [
            { key: :sol_palmanova, workout: :sa_creu_2026, name: "Sol de Mallorca – Palmanova", description: "La sortie du quartier jusqu'à la carretera de Cala Figuera.",
              visibility: "followers_only", zone_acknowledged: true, start: [ 39.48309, 2.52147 ], end: [ 39.51724, 2.52136 ] }
          ]
        },
        {
          username: "kasia",
          discoverable: "members",
          leaderboard_category: "women",
          email: "kasia@demo.allure.rocks",
          display_name: "Kasia Nowak",
          bio: "Wrocław, Sępolno. Running most days, skiing when there is snow.",
          locale: "en",
          theme: "dark",
          time_zone: "Europe/Warsaw",
          equipment: [
            { label: "Adidas Boston", type: "shoes" },
            { label: "Fischer Speedmax", type: "skis" }
          ],
          privacy_zones: [ { name: "Home", latitude: 51.1101, longitude: 17.1063, radius_meters: 300 } ],
          built_in_profiles: { public: { auto_publish: true, auto_publish_exclude_commute: true } },
          workouts: [
            { key: :half_2024, file: "Activity/2024/Activity_20240615_001_000_Running_Watch6,9_3f7f73b11f19f2f63f25fb2d25b46c0c.fit",
              title: "Wrocław night half marathon 2024", equipment: [ "Adidas Boston" ], publish: :public },
            { key: :run_2025_06_06, file: "Activity/2025/Activity_20250606_001_000_Running_Watch7,5_27fa41dce6ad7a2afbffe6d2497d9b24.fit",
              title: "Last long run before the half", equipment: [ "Adidas Boston" ], publish: :public },
            { key: :half_2025, file: "Activity/2025/Activity_20250614_001_000_Running_Watch7,5_a0c7503f20cd2bfd9f25dde1200b8b6a.fit",
              title: "Wrocław night half marathon 2025", description: "Negative split, finally.", equipment: [ "Adidas Boston" ], publish: :public },
            { key: :run_2025_07_02, file: "Activity/2025/Activity_20250702_001_000_Running_Watch7,5_d461f73efc9ab15a23aec923a8a05816.fit",
              title: "Odra embankment, easy", equipment: [ "Adidas Boston" ], publish: :public },
            { key: :run_2025_08_20, file: "Activity/2025/Activity_20250820_001_000_Running_Watch7,5_e55b11c38ec1a72815b3cdc05057497d.fit",
              title: "Evening 10k", equipment: [ "Adidas Boston" ], publish: :public },
            { key: :run_2025_09_05, file: "Activity/2025/Activity_20250905_001_000_Running_Watch7,5_17704c24197361bb9e6c179a11abba7c.fit",
              title: "14k with strides", equipment: [ "Adidas Boston" ] },
            { key: :run_2025_09_16, file: "Activity/2025/Activity_20250916_001_000_Running_Watch7,5_1e198e51654d3cb8cf0bee6d6a503437.fit",
              title: "Kanałowa and back, 14k", equipment: [ "Adidas Boston" ], publish: :public },
            { key: :run_2025_09_21, file: "Activity/2025/Activity_20250921_001_000_Running_Watch7,5_e8c85118b62de1da83a6f6cf4e26a760.fit",
              title: "Sunday 12k", equipment: [ "Adidas Boston" ], publish: :public },
            { key: :run_2025_11_23, file: "Activity/2025/Activity_20251123_001_000_Running_Watch7,5_35dc720a74d661b05c61decc42fda578.fit",
              title: "Cold 7k", equipment: [ "Adidas Boston" ] },
            { key: :walk_2025_12_14, file: "Activity/2025/Activity_20251214_011_000_Walking_Watch7,5_d1e031650b86c52af90aca41789d51e3.fit",
              title: "Christmas market walk" },
            { key: :walk_2025_12_23, file: "Activity/2025/Activity_20251223_011_000_Walking_Watch7,5_971736c1cd58fbaadb2a1d3a6ff8e3e6.fit",
              title: "Walk to the Olympic stadium" },
            { key: :walk_2026_01_04, file: "Activity/2026/Activity_20260104_011_000_Walking_Watch7,5_a66afce3f6e5a698086659a01f96e839.fit",
              title: "Sunday walk" },
            { key: :ride_2026_01, file: "Activity/2026/Activity_20260116_002_000_Cycling_Watch7,5_64aaac47310ebae8fbd6f8673228250c.fit",
              title: "City bike errand", commute: true },
            { key: :run_2026_02_08, file: "Activity/2026/Activity_20260208_001_000_Running_Watch7,5_fce69db04b37362555eabaf752f772d5.fit",
              title: "Slushy 10k", equipment: [ "Adidas Boston" ], publish: :public },
            { key: :xc_2026_03_08, file: "Activity/2026/Activity_20260308_012_000_Cross-Country-Skiing_EpixGen2Pro51_80eab2e4cf3a5b0bb1513a60eb43c57b.fit",
              title: "Bruksvallarna, day 1", equipment: [ "Fischer Speedmax" ], publish: :public },
            { key: :xc_2026_03_09, file: "Activity/2026/Activity_20260309_012_000_Cross-Country-Skiing_EpixGen2Pro51_8d720b0557092be5286466bc9b80dba8.fit",
              title: "Bruksvallarna, 25 km classic", equipment: [ "Fischer Speedmax" ], publish: :public },
            { key: :xc_2026_03_12, file: "Activity/2026/Activity_20260312_012_000_Cross-Country-Skiing_EpixGen2Pro51_c8c76bbf0facaa48e5f2df7eb7707ec4.fit",
              title: "Bruksvallarna to Kariknallen", equipment: [ "Fischer Speedmax" ], publish: :public },
            { key: :run_2026_04_05, file: "Activity/2026/Activity_20260405_001_000_Running_Watch7,5_7d38bb7a46914d9e9d963d493b7fde00.fit",
              title: "15k, spring at last", equipment: [ "Adidas Boston" ], publish: :public },
            { key: :xc_2026_04_06, file: "Activity/2026/Activity_20260406_012_042_Cross-Country-Skiing_Skate-Skiing_EpixGen2Pro51_f197d4013b70a31540aad0eaeab4f00f.fit",
              title: "Åre skate session", equipment: [ "Fischer Speedmax" ], publish: :public },
            { key: :half_2026, file: "Activity/2026/Activity_20260419_001_000_Running_Watch7,5_91a0ce7bf002874b82c33825dcc11d03.fit",
              title: "Spring half, solo", equipment: [ "Adidas Boston" ], publish: :public }
          ],
          segments: [
            { key: :kanalowa, workout: :run_2025_09_16, name: "Kanałowa embankment", visibility: "public",
              start: [ 51.11142, 17.11086 ], end: [ 51.10212, 17.12315 ] },
            { key: :half_route, workout: :half_2024, name: "Wrocław night half course", kind: "route" }
          ]
        },
        {
          username: "owen",
          discoverable: "members",
          leaderboard_category: "men",
          email: "owen@demo.allure.rocks",
          display_name: "Owen Hughes",
          bio: "Weymouth. Windsurfing in Portland Harbour, the coast path on foot.",
          locale: "en",
          theme: "light",
          unit_system: "imperial",
          time_zone: "Europe/London",
          equipment: [
            { label: "Fanatic Blast 120", type: "board" },
            { label: "Starboard Touring 12'6", type: "board", description: "Paddle board." },
            { label: "Scarpa Terra GTX", type: "shoes" }
          ],
          workouts: [
            { key: :windsurf_2021, file: "Activity/2022/Activity_20210706_043_Windsurfing_COROS-VERTIX_88afc123a12a01d03b3db3da688aaa25.fit",
              title: "Portland Harbour, 5 hours of westerly", equipment: [ "Fanatic Blast 120" ], publish: :public },
            { key: :sup_hayling, file: "Activity/2022/Activity_20220319_037_000_Stand-Up-Paddleboarding_Fenix6_524c331f81ba314e76187bac5aa789b1.fit",
              title: "Paddle around Hayling Island", equipment: [ "Starboard Touring 12'6" ], publish: :public },
            { key: :windsurf_2022_04, file: "Activity/2022/Activity_20220410_043_Windsurfing_COROS-APEX-Pro_0356ff9cdb4cdf334010dca9d17130fb.fit",
              title: "Portland Harbour, flat and fast", equipment: [ "Fanatic Blast 120" ], publish: :public },
            { key: :lulworth_walk, file: "Activity/2022/Activity_20221112_011_Walking_COROS-APEX-Pro_9a95ba0b408c37ee51cfaf4212046779.fit",
              title: "Lulworth Cove and Durdle Door" },
            { key: :windsurf_2023, file: "Activity/2023/Activity_20230325_043_Windsurfing_COROS-VERTIX-2_b9d9ba8c81afc18f1c11316e124819f9.fit",
              title: "Poole Harbour session", equipment: [ "Fanatic Blast 120" ], publish: :public },
            { key: :boscastle, file: "Activity/2024/Activity_20240601_017_Hiking_COROS-APEX-2-Pro_04f0d5d7c8d0983accbb2dc95b72138b.fit",
              title: "Boscastle to Crackington Haven", description: "South West Coast Path, day 1.", equipment: [ "Scarpa Terra GTX" ], publish: :public },
            { key: :tintagel, file: "Activity/2024/Activity_20240602_017_Hiking_COROS-APEX-2-Pro_0e668801b1e8a6dc08a19338ec5667fc.fit",
              title: "Boscastle to Tintagel", description: "South West Coast Path, day 2.", equipment: [ "Scarpa Terra GTX" ], publish: :public },
            { key: :bude, file: "Activity/2024/Activity_20240603_017_Hiking_COROS-APEX-2-Pro_be2edf4a56f9d2630102e1b20c675b97.fit",
              title: "Bude to Crackington Haven", description: "South West Coast Path, day 3.", equipment: [ "Scarpa Terra GTX" ], publish: :public },
            { key: :porlock, file: "Activity/2024/Activity_20240904_017_Hiking_COROS-APEX-2-Pro_30836f72582bcd57e9f2a04498d15b7c.fit",
              title: "Porlock Weir to Countisbury", equipment: [ "Scarpa Terra GTX" ], publish: :public },
            { key: :windsurf_2024, file: "Activity/2024/Activity_20241015_043_Windsurfing_COROS-Wearables_c3769089db57ec6d9e7a68c9cad0d0b3.fit",
              title: "October gusts, Portland Harbour", equipment: [ "Fanatic Blast 120" ], publish: :public },
            { key: :combe_martin, file: "Activity/2025/Activity_20250719_017_Hiking_COROS-Wearables_c98366249e5f4a9a1c7283322616d810.fit",
              title: "Combe Martin to Ilfracombe", equipment: [ "Scarpa Terra GTX" ], publish: :public }
          ],
          segments: [
            { key: :boscastle_path, workout: :boscastle, name: "Boscastle to Crackington Haven", description: "The coast path over Penally Hill.",
              visibility: "public", start: [ 50.68983, -4.69189 ], end: [ 50.74104, -4.63338 ] }
          ]
        },
        {
          username: "lucas",
          discoverable: "members",
          leaderboard_category: "men",
          email: "lucas@demo.allure.rocks",
          display_name: "Lucas Peeters",
          bio: "Diest. Short runs from the door, the Allerheiligenberg trails at the weekend.",
          locale: "en",
          theme: "light",
          time_zone: "Europe/Brussels",
          equipment: [ { label: "Saucony Peregrine", type: "shoes" } ],
          privacy_zones: [ { name: "Home", latitude: 50.9917, longitude: 5.0468, radius_meters: 200 } ],
          workouts: [
            { key: :run_0119, file: "Activity/2026/Activity_20260119_001_000_Running_Fenix7x_e5dc331f7d2a34526cc47b89871574f8.fit",
              title: "Schaluinveld 3.5k", equipment: [ "Saucony Peregrine" ] },
            { key: :run_0122, file: "Activity/2026/Activity_20260122_001_000_Running_Fenix7x_52742cae0722e85f26ca8580b0b82c08.fit",
              title: "Schaluinveld 3.5k, again", equipment: [ "Saucony Peregrine" ] },
            { key: :trail_0123, file: "Activity/2026/Activity_20260123_001_003_Running_Trail_Fenix7x_815a6cdbcc35b657bbff3b35f4eb0a95.fit",
              title: "Short trail loop", equipment: [ "Saucony Peregrine" ], publish: :public },
            { key: :trail_0125, file: "Activity/2026/Activity_20260125_001_003_Running_Trail_Fenix7x_9564febcecfc495e1a5329b22d12567f.fit",
              title: "Allerheiligenberg trail", equipment: [ "Saucony Peregrine" ], publish: :public },
            { key: :trail_0131, file: "Activity/2026/Activity_20260131_001_003_Running_Trail_Fenix7x_22c1a9241ce3bd5b38e71cb8b9ea2a25.fit",
              title: "Allerheiligenberg, muddy", equipment: [ "Saucony Peregrine" ], publish: :public },
            { key: :trail_0207, file: "Activity/2026/Activity_20260207_001_003_Running_Trail_Fenix7x_a84c7a5b2924c1b0bee037ffbbc557d3.fit",
              title: "Trail from the station", equipment: [ "Saucony Peregrine" ], publish: { audience: :public, delay: "1_day" } },
            { key: :trail_0215, file: "Activity/2026/Activity_20260215_001_003_Running_Trail_Fenix7x_a790a6293770eda5fbd090ebfe8203b6.fit",
              title: "Long trail Sunday", equipment: [ "Saucony Peregrine" ], publish: :public }
          ],
          batches: [
            {
              sport: "trail",
              notes: "Two trails from the watch and a file the export broke.",
              files: [
                { key: :trail_0210, file: "Activity/2026/Activity_20260210_001_003_Running_Trail_Fenix7x_aebb761a3109b7a8eb1da0f9aef38f45.fit" },
                { key: :trail_0212, file: "Activity/2026/Activity_20260212_001_003_Running_Trail_Fenix7x_20592feb9e73ef3d036bd98dc9b82966.fit" },
                { fixture: "gpx/malformed.gpx", as: "trail_0214.gpx" }
              ]
            }
          ],
          segments: [
            # Ends short of the home zone, so the course can be shared without
            # acknowledging a zone crossing and its efforts stay on the board.
            { key: :allerheiligenberg, workout: :trail_0125, name: "Allerheiligenberg to Schaluinveld", visibility: "public",
              start: [ 50.98348, 5.04759 ], end: [ 50.98900, 5.04760 ] },
            { key: :schaluinveld_route, workout: :run_0119, name: "Schaluinveld 3.5k", kind: "route" }
          ]
        },
        {
          username: "nina",
          email: "nina@demo.allure.rocks",
          display_name: "Nina Lefèvre",
          bio: "Nouvelle ici.",
          locale: "fr",
          theme: "light",
          time_zone: "Europe/Paris",
          second_factor: false
        },
        {
          username: "promo_bot",
          email: "promo@demo.allure.rocks",
          display_name: "Best Deals",
          bio: "Visit our site for the best deals on bikes!!!",
          locale: "en",
          theme: "light",
          time_zone: "UTC"
        }
      ],

      follows: [
        { from: "marie", to: "sophie" }, { from: "sophie", to: "marie" },
        { from: "marie", to: "tom" }, { from: "tom", to: "marie" },
        { from: "marie", to: "joan" }, { from: "marie", to: "paul" }, { from: "paul", to: "marie" },
        { from: "paul", to: "tom" },
        { from: "tom", to: "eva" }, { from: "eva", to: "tom" },
        { from: "tom", to: "joan" }, { from: "joan", to: "tom" },
        { from: "tom", to: "ines" }, { from: "ines", to: "tom" },
        { from: "joan", to: "ines" }, { from: "ines", to: "joan" },
        { from: "eva", to: "joan" }, { from: "eva", to: "kasia" },
        { from: "kasia", to: "marie" }, { from: "kasia", to: "tom" }, { from: "tom", to: "kasia" },
        { from: "sophie", to: "ines" }, { from: "ines", to: "sophie" },
        { from: "owen", to: "tom" }, { from: "owen", to: "kasia", decision: "reject" },
        { from: "lucas", to: "marie" }, { from: "lucas", to: "tom" },
        { from: "nina", to: "marie", decision: "pending" }
      ],

      participations: [
        { owner: "tom", workout: :sa_creu_2026, participant: "joan", decision: "confirm", with_workout: :sa_creu_2026 },
        { owner: "tom", workout: :sa_creu_2026, participant: "ines", decision: "confirm", with_workout: :sa_creu_2026 },
        { owner: "tom", workout: :sa_creu_2026, participant: "eva", decision: "confirm", with_workout: :sa_creu_2026 },
        { owner: "tom", workout: :ultra, participant: "joan", decision: "confirm", with_workout: :ultra },
        { owner: "tom", workout: :ultra, participant: "ines" },
        { owner: "tom", workout: :portals_vells_long_run, participant: "ines", decision: "confirm", with_workout: :portals_vells_trail },
        { owner: "tom", workout: :portals_vells_long_run, participant: "joan", decision: "confirm", with_workout: :portals_vells_trail },
        { owner: "tom", workout: :jan_wilsbrug_run, participant: "eva", decision: "confirm", with_workout: :jan_wilsbrug_run },
        { owner: "marie", workout: :sancy_day1, participant: "sophie", decision: "confirm" },
        { owner: "marie", workout: :cucheron, participant: "paul", decision: "decline" }
      ],

      comments: [
        { key: :ultra_joan, author: "joan", owner: "tom", workout: :ultra, body: "What a day. Thanks for pacing me up the Galatzó, I had nothing left by then." },
        { key: :ultra_ines, author: "ines", owner: "tom", workout: :ultra, parent: :ultra_joan, body: "Merci pour la journée, mes jambes s'en souviennent encore." },
        { key: :ultra_tom, author: "tom", owner: "tom", workout: :ultra, parent: :ultra_joan, body: "Same time next year?" },
        { author: "marie", owner: "tom", workout: :ultra, body: "Bravo à tous les trois !" },
        { author: "eva", owner: "tom", workout: :ultra, body: "Wrong activity, sorry!", state: :deleted },
        { author: "lucas", owner: "tom", workout: :ultra, body: "Great deals on trail shoes at my site, link in bio.", state: :removed },
        { key: :sophie_run_marie, author: "marie", owner: "sophie", workout: :strassen_2019_09, body: "Belle régularité !" },
        { author: "sophie", owner: "sophie", workout: :strassen_2019_09, parent: :sophie_run_marie, body: "Merci ! On y retourne dimanche ?" },
        { author: "joan", owner: "tom", workout: :blanes_hills_run, body: "That climb never gets easier. Strong pace on the ridge!" },
        { author: "ines", owner: "tom", workout: :portals_vells_long_run, body: "Belle sortie ! La traversée valait le détour." },
        { author: "tom", owner: "kasia", workout: :half_2025, body: "Strong negative split!" },
        { author: "eva", owner: "kasia", workout: :half_2025, body: "Congrats!" },
        { author: "paul", owner: "marie", workout: :alpe, body: "On the list for next summer." }
      ],

      closed_threads: [ { owner: "sophie", workout: :gerardmer_ski } ],

      reactions: [
        { by: "joan", owner: "tom", workout: :ultra, kind: "beer" },
        { by: "ines", owner: "tom", workout: :ultra, kind: "energy" },
        { by: "marie", owner: "tom", workout: :ultra, kind: "like" },
        { by: "eva", owner: "tom", workout: :ultra, kind: "coffee" },
        { by: "kasia", owner: "tom", workout: :ultra, kind: "energy" },
        { by: "tom", owner: "ines", workout: :ultra, kind: "beer" },
        { by: "sophie", owner: "marie", workout: :alpe, kind: "energy" },
        { by: "paul", owner: "marie", workout: :alpe, kind: "like" },
        { by: "marie", owner: "sophie", workout: :strassen_2019_09, kind: "coffee" },
        { by: "tom", owner: "kasia", workout: :half_2025, kind: "energy" },
        { by: "eva", owner: "kasia", workout: :half_2025, kind: "like" },
        { by: "tom", owner: "eva", workout: :rowing, kind: "coffee" },
        { by: "owen", owner: "tom", workout: :waterland, kind: "like" },
        { by: "lucas", owner: "marie", workout: :chamonix, kind: "energy" },
        { by: "joan", owner: "tom", workout: :portals_vells_long_run, kind: "energy" },
        { by: "marie", owner: "tom", workout: :blanes_hills_run, kind: "like" },
        { by: "eva", owner: "tom", workout: :florida_beach_run, kind: "coffee" }
      ],

      opt_outs: [ { user: "ines", owner: "tom", segment: :sa_creu } ],

      copies: [ { user: "eva", owner: "tom", segment: :jan_wilsbrug, reversed: true } ],

      api: [
        {
          user: "tom",
          tokens: [
            { name: "Local scripts", scopes: ApiToken::SCOPES, mcp_geometry: "filtered" },
            { name: "Old laptop", scopes: [ "read" ], revoked: true }
          ],
          webhooks: [
            { url: "https://example.com/hooks/allure", description: "Paused until the receiver is deployed.", active: false }
          ]
        }
      ],

      admin: {
        operator: "marie",
        invitations: [ "invite@demo.allure.rocks" ],
        suspended: [ { username: "promo_bot", reason: "Spam" } ],
        identities: [
          { username: "nina", provider: "oidc", issuer: "http://dex.test:5556/dex", subject: "6b3a3b1e-7d1a-4c3e-9f0b-2a4a1b6d8c01" }
        ]
      }
    }.freeze
  end
end
