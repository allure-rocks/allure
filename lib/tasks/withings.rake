# frozen_string_literal: true

namespace :withings do
  # Feasibility check for docs/dev/REMOTE-IMPORTS.md against a real Withings
  # account. Writes nothing to the database and never prints the password,
  # the session id or the userid (W1 in docs/dev/REMOTE-IMPORTS.md part 4).
  #
  #   dip rails withings:probe
  #   WITHINGS_EMAIL=… DAYS=30 DOWNLOAD=1 TCX_PATH=tmp/withings-probe.tcx \
  #     SESSION_FILE=tmp/withings-probe.json dip rails withings:probe
  #
  # With SESSION_FILE the session id and userid are kept in that file (mode
  # 0600, development only, delete it afterwards) and later runs skip the
  # sign-in — which also exercises the session's real lifetime; a dead
  # stored session re-signs in on its own. DURATION (seconds, default
  # 86 400, the duration Withings grants) tries another session length.
  desc "Sign in to Withings's private API and report each step (nothing stored)"
  task probe: :environment do
    require "io/console"
    require "stringio"
    require "tempfile"

    withings = Allure::Withings
    step = ->(label) { puts "\n== #{label}" }
    # Never a credential: only that the value is there and how long it is.
    describe_secret = ->(value) { value.present? ? "present (#{value.to_s.length} chars)" : "absent" }

    session_file = ENV["SESSION_FILE"].presence&.then { Rails.root.join(it) }
    save_session = lambda do |session_id, user_id|
      next unless session_file

      File.write(session_file, JSON.generate(session_id:, user_id:, created_at: Time.current.utc.iso8601),
                 perm: 0o600)
      File.chmod(0o600, session_file)
    end

    http = withings::Http.new
    reused = session_file&.exist?
    session_id = nil
    user_id = nil
    if reused
      step.call("Reusing the session stored in #{session_file.relative_path_from(Rails.root)} (no sign-in)")
      stored = JSON.parse(session_file.read)
      session_id = stored.fetch("session_id")
      user_id = stored.fetch("user_id")
      puts "  session: #{describe_secret.call(session_id)}; stored #{stored['created_at']}"
      begin
        today = Time.current.to_date
        withings::Client.new(session_id:, user_id:, http:).activities_in_window(from: today, to: today)
      rescue withings::Error::ApiStatus => error
        puts "  the stored session no longer opens the account (status #{error.status}) — signing in again"
        session_id = nil
      end
    end
    if session_id.nil?
      email = ENV["WITHINGS_EMAIL"].presence || (print("Withings e-mail: ") || STDIN.gets&.chomp).to_s
      password = ENV["WITHINGS_PASSWORD"].presence || STDIN.getpass("Withings password: ")
      abort "An e-mail and a password are required." if email.blank? || password.blank?
      duration = ENV.fetch("DURATION", withings::Session::DAILY_DURATION)

      step.call("Sign-in (POST /cgi-bin/auth, duration #{duration} s)")
      begin
        signed_in = withings::Session.new(http:).sign_in(email:, password:, duration:)
      ensure
        password = nil
      end
      session_id = signed_in.session_id
      puts "  login answered; body keys: #{signed_in.body['body']&.keys&.join(', ')}"
      login_body = signed_in.body["body"] || {}
      puts "  duration: #{login_body['duration'].inspect}; login_method: #{login_body['login_method'].inspect}; " \
           "require_secure_session: #{login_body['require_secure_session'].inspect}; " \
           "is_secure: #{login_body['is_secure'].inspect}"
      puts "  session id: #{describe_secret.call(session_id)}; account id: #{describe_secret.call(signed_in.account_id.to_s)}"
      save_session.call(session_id, signed_in.account_id)

      step.call("Account users (POST /cgi-bin/account)")
      users = withings::Session.new(http:).users(signed_in)
      puts "  #{users.size} user(s)"
      users.each_with_index do |user, index|
        puts "  user #{index + 1}: id #{describe_secret.call(user['id'].to_s)}; keys: #{user.keys.join(', ')}"
      end
      user_id = ENV["WITHINGS_USER_ID"].presence || users.dig(0, "id")
      if user_id.to_s.empty?
        save_session.call(session_id, nil) if session_file
        abort "No user id in the account users answer (keys: #{users.first&.keys&.join(', ')})"
      end
      save_session.call(session_id, user_id)
    end

    client = withings::Client.new(session_id:, user_id:, http:)

    days = Integer(ENV.fetch("DAYS", 30))
    from = days.days.ago.to_date
    to = Time.current.to_date
    step.call("Workouts of the last #{days} days (30-day windows)")
    activities = client.activities(from:, to:)
    puts "  #{activities.size} workout(s)"
    activities.first(15).each do |activity|
      flags = +""
      flags << (activity.positioned? ? "gps " : "indoor ")
      flags << "sleep " if activity.sleep?
      flags << "auto " if activity.auto_detected?
      puts format("  %-12s %-20s → %-20s cat=%-4s (%s) %s| data: %s",
                  activity.id.to_s, activity.started_at&.strftime("%F %T"),
                  activity.ended_at&.strftime("%F %T"), activity.category,
                  withings::SportMapping.name(activity.category), flags,
                  activity.data&.keys&.join(","))
    end

    step.call("Wide-window check (one getbyuserid call over 90 days)")
    begin
      wide = client.activities_in_window(from: 90.days.ago.to_date, to:)
      puts "  answered: #{wide.size} workout(s) in one call"
      if (item = wide.first&.raw)
        puts "  item keys: #{item.keys.join(', ')}"
        puts "  item without data/gps: #{item.except('data', 'gps').inspect}"
      end
    rescue withings::Error::ApiStatus => error
      puts "  refused: #{error.message}"
    end

    if ENV["DOWNLOAD"].present?
      # Up to three positioned sessions, newest first: an account may hold
      # sparse recent ones and a real track further back (observed
      # 2026-11-01: a sparse answer on 2026-08-10, the next track on
      # 2026-06-09 — pass DAYS wide enough to reach it).
      positioned = activities.select(&:positioned?).first(3)
      # A real indoor session: heart-rate aggregates and no sleep keys, not
      # a sleep summary and not an auto-detected step summary.
      indoor = activities.find do |activity|
        !activity.positioned? && !activity.sleep? && activity.ended_at && activity.data&.key?("hr_average")
      end
      sessions = positioned.map { |activity| [ "positioned", activity ] }
      sessions << [ "indoor", indoor ]
      sessions.reject { |_, activity| activity.nil? }.each do |label, activity|
        begin
          step.call("#{label} session #{activity.id} (#{withings::SportMapping.name(activity.category)}): series and TCX round trip")
          puts "  gps: #{activity.gps.inspect}"
          puts "  data: #{activity.data.inspect}"
          location = client.location_series(activity.started_at, activity.ended_at)
          heart_rate = client.heart_rate_series(activity.started_at, activity.ended_at)
          report_series = lambda do |series, name|
            dates = series.dates
            puts "  #{name}: #{dates.size} samples" + (dates.empty? ? "" : ", #{Time.at(dates.first).utc.iso8601} → #{Time.at(dates.last).utc.iso8601}")
            widths = series.rows.map(&:length).uniq
            puts "    row arities: #{widths.join(', ')}"
            series.rows.transpose.each_with_index do |column, index|
              values = column.map(&:to_f)
              puts format("    column %d: min %s  mean %s  max %s", index,
                          values.min.round(4), (values.sum / values.length).round(4), values.max.round(4))
            end
          end
          report_series.call(location, "location")
          report_series.call(heart_rate, "heart rate")

          # A GPS session whose location answer is sparse: where does this
          # watch's track live? The official API's high-frequency companion
          # is the first suspect (§7c.1) — and the next positioned session
          # may hold the real track.
          if location.dates.length < 2
            puts "  sparse location answer — trying getintradayactivity"
            begin
              intraday = client.intraday_activity(activity.started_at, activity.ended_at)
              inner = intraday["body"]
              puts "  intraday body keys: #{inner&.keys&.join(', ')}"
              series = inner&.dig("series") || inner&.dig("intraday")
              if series.is_a?(Hash)
                puts "  intraday: a hash of #{series.length} keys (#{series.first&.first.inspect} → #{series.first&.last.class.name})"
              elsif series.is_a?(Array)
                puts "  intraday: #{series.length} items; first: #{series.first.inspect.to_s[0, 300]}"
              else
                puts "  intraday: #{series.class.name}"
              end
            rescue withings::Error => error
              puts "  intraday refused: #{error.class.name.demodulize}: #{error.message}"
            end
            next if label == "positioned"
          end

          tcx = withings::TcxWriter.build(activity:, location:, heart_rate:)
          if (base = ENV["TCX_PATH"].presence&.then { Rails.root.join(it) })
            path = base.sub_ext("-#{label}#{base.extname}")
            File.write(path, tcx)
            puts "  TCX written to #{path.relative_path_from(Rails.root)} (#{tcx.bytesize} bytes)"
          else
            puts "  TCX: #{tcx.bytesize} bytes"
          end

          track = Allure::Tcx::Parser.new.parse(StringIO.new(tcx))
          sport = Sport.find_by(slug: withings::SportMapping.slug(activity.category) || "fitness")
          metrics = Allure::Gpx::Analyzer.new(
            stopped_speed_threshold_km_h: sport.stopped_speed_threshold,
            records_elevation: sport.records_elevation,
            grade_adjusted_pace: sport.grade_adjusted_pace?,
            speed_ceiling_km_h: sport.speed_ceiling_km_h
          ).analyze(track)
          puts "  parsed: creator #{track.creator.inspect}; #{metrics.points_count} points; " \
               "positioned: #{track.positioned?}"
          puts "  analysis: #{metrics.duration.round}s, #{metrics.distance.round} m, " \
               "hr avg/max #{metrics.average_heart_rate.inspect}/#{metrics.max_heart_rate.inspect}, " \
               "calories #{metrics.calories.inspect}, laps #{track.laps.length}"
        rescue withings::Error::NoSamples => error
          puts "  no original to build: #{error.message}"
        rescue StandardError => error
          puts "  round trip failed: #{error.class.name}: #{error.message}"
        end
      end
    end

    step.call("Expired-session status (one call with a corrupted session id)")
    begin
      corrupted = withings::Client.new(session_id: "corrupted-#{session_id.to_s[0, 4]}", user_id:, http:)
      corrupted.activities_in_window(from:, to:)
      puts "  unexpectedly answered"
    rescue withings::Error::ApiStatus => error
      puts "  status #{error.status} (#{error.message})"
    rescue withings::Error => error
      puts "  #{error.class.name.demodulize}: #{error.message}"
    end

    puts "\nProbe succeeded."
  rescue Allure::Withings::Error => error
    hint = error.is_a?(Allure::Withings::Error::ApiStatus) && reused ? " (the stored session no longer opens the account — rm #{session_file.relative_path_from(Rails.root)} to sign in again)" : ""
    abort "\nProbe failed: #{error.class.name.demodulize}: #{error.message}#{hint}"
  end
end
