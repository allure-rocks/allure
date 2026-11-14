# frozen_string_literal: true

namespace :zwift do
  # Feasibility check for PLAN_REMOTE_IMPORTS.md §7d against a real Zwift
  # account. Writes nothing to the database and never prints the password,
  # the access token or the refresh token (Z1 in RUNBOOK_REMOTE_IMPORTS.md
  # part 5).
  #
  #   dip sh
  #   TOKEN_FILE=tmp/zwift-probe.json DOWNLOAD=1 bin/rails zwift:probe
  #
  # `dip rails` does not forward arbitrary host environment variables; set
  # them inside the container shell.
  #
  # With TOKEN_FILE the refresh token is kept in that file (mode 0600,
  # development only, delete it afterwards) and later runs skip the sign-in —
  # which also measures the refresh token's real lifetime. A dead stored
  # token falls back to the sign-in prompt.
  desc "Sign in to Zwift's mobile API and report each step (nothing stored)"
  task probe: :environment do
    require "io/console"
    require "tempfile"

    zwift = Allure::Zwift
    step = ->(label) { puts "\n== #{label}" }
    secret = ->(value) { value.to_s.empty? ? "absent" : "present (#{value.to_s.length} chars)" }
    moment = lambda do |time|
      time ? "#{time.utc.iso8601} (#{((time - Time.now) / 3600.0).round(1)} h)" : "unknown"
    end

    token_file = ENV["TOKEN_FILE"].presence&.then { Rails.root.join(it) }
    save = lambda do |tokens, player_id, user_agent|
      next unless token_file

      File.write(token_file, JSON.generate(
        refresh_token: tokens.refresh_token,
        player_id: player_id,
        user_agent: user_agent,
        saved_at: Time.now.utc.iso8601
      ), perm: 0o600)
      File.chmod(0o600, token_file)
    end

    http = zwift::Http.new
    auth = zwift::Auth.new(http:)
    tokens = nil
    player_id = nil

    report_refresh = lambda do |refreshed, previous|
      rotated = refreshed.refresh_token.to_s != previous.to_s
      puts "  accepted; refresh token #{rotated ? 'rotated' : 'unchanged'}; " \
           "expires_in raw #{refreshed.expires_in.inspect} → #{moment.call(refreshed.expires_at)}"
      puts "  refresh_expires_in raw #{refreshed.refresh_expires_in.inspect}; " \
           "refresh token until #{moment.call(refreshed.refresh_expires_at)}; " \
           "new refresh token: #{secret.call(refreshed.refresh_token)}"
    end

    if token_file&.exist?
      step.call("Reusing the refresh token stored in #{token_file.relative_path_from(Rails.root)} (no sign-in)")
      stored = JSON.parse(token_file.read)
      player_id = stored["player_id"]
      puts "  refresh token: #{secret.call(stored['refresh_token'])}; stored #{stored['saved_at']}; " \
           "user agent #{stored['user_agent'].inspect}"
      begin
        tokens = auth.refresh(refresh_token: stored["refresh_token"])
        report_refresh.call(tokens, stored["refresh_token"])
        save.call(tokens, player_id, http.user_agent)
      rescue zwift::Error::RefreshRejected => error
        puts "  rejected: #{error.message} — the stored refresh token has died; signing in again"
      end
    end

    if tokens.nil?
      email = ENV["ZWIFT_EMAIL"].presence || (print("Zwift e-mail: ") || STDIN.gets&.chomp).to_s
      password = ENV["ZWIFT_PASSWORD"].presence || STDIN.getpass("Zwift password: ")
      abort "A Zwift e-mail and a password are required." if email.empty? || password.empty?

      step.call("Sign-in (password grant, client #{zwift::Auth::CLIENT_ID})")
      begin
        tokens = auth.sign_in(email:, password:)
      ensure
        password = nil
      end
      puts "  access token: #{secret.call(tokens.access_token)}; refresh token: #{secret.call(tokens.refresh_token)}"
      puts "  expires_in raw #{tokens.expires_in.inspect} → access token until #{moment.call(tokens.expires_at)}"
      puts "  refresh_expires_in raw #{tokens.refresh_expires_in.inspect}; " \
           "refresh token until #{moment.call(tokens.refresh_expires_at)}; " \
           "token_type #{tokens.raw['token_type'].inspect}; scope #{tokens.raw['scope'].inspect}"
      save.call(tokens, player_id, http.user_agent)

      if tokens.refresh_token.to_s.empty?
        puts "  no refresh token: the provider could not keep the connection"
      else
        step.call("Refresh grant right after the sign-in (does the refresh token rotate?)")
        begin
          refreshed = auth.refresh(refresh_token: tokens.refresh_token)
          report_refresh.call(refreshed, tokens.refresh_token)
          tokens = refreshed
          save.call(tokens, player_id, http.user_agent)
        rescue zwift::Error::RefreshRejected => error
          puts "  rejected: #{error.message} — keeping the sign-in access token"
        end
      end
    end

    client = zwift::Client.new(
      refresh_token: tokens.refresh_token,
      access_token: tokens.access_token,
      expires_at: tokens.expires_at,
      player_id:,
      http:,
      on_tokens: lambda do |rotated_tokens|
        tokens = rotated_tokens
        save.call(rotated_tokens, player_id, http.user_agent)
      end
    )

    step.call("Profile (GET /api/profiles/me)")
    profile = client.profile
    player_id = profile["id"]&.to_s
    puts "  id: #{player_id.inspect}; keys: #{profile.keys.sort.join(', ')}"
    puts "  user agent: #{http.user_agent.inspect}" \
         "#{http.user_agent_fallback_status ? " (neutral UA refused with HTTP #{http.user_agent_fallback_status}, mobile UA accepted)" : ''}"

    step.call("Activity list (GET /api/profiles/{id}/activities?start=&limit=)")
    page = client.activities(start: 0, limit: zwift::Client::PAGE_SIZE)
    puts "  page 1: #{page.size} rows"
    page.first(5).each do |activity|
      puts format("  %-10s %-19s %-7s world %-2s %9s m  bucket=%s key=%s  %s",
                  activity.id, activity.started_at&.strftime("%F %T"), activity.sport, activity.world_id,
                  activity.distance_m&.round, activity.fit_bucket.present? ? "yes" : "no",
                  activity.fit_key.present? ? "yes" : "no", activity.name)
    end

    step.call("Pagination and the activity cap")
    start = 0
    pages = 0
    total = 0
    oldest = nil
    loop do
      rows = start.zero? ? page : client.activities(start:, limit: zwift::Client::PAGE_SIZE)
      break if rows.empty?

      pages += 1
      total += rows.size
      oldest = [ oldest, rows.filter_map(&:started_at).min ].compact.min
      break if rows.size < zwift::Client::PAGE_SIZE || pages >= zwift::Client::MAX_PAGES

      start += zwift::Client::PAGE_SIZE
    end
    puts "  #{pages} page(s), #{total} activities, oldest #{oldest&.utc&.iso8601}"
    puts "  the reference reports a 250-activity cap" if total >= 250

    if ENV["DOWNLOAD"].present? && (activity = page.find { |row| row.fit_bucket.present? && row.fit_key.present? })
      step.call("FIT download of #{activity.id}")
      puts "  bucket: #{activity.fit_bucket.inspect}; key: #{activity.fit_key.inspect}"
      Tempfile.create([ "zwift-probe", ".fit" ], binmode: true) do |file|
        begin
          client.download_fit(activity, io: file)
        rescue ArgumentError => error
          abort "  the FIT pointer is not a safe S3 object: #{error.message}"
        end
        puts "  #{file.size} bytes; FIT header present"
        track = Allure::Fit::Parser.new.parse(file)
        points = track.segments.flat_map(&:points)
        positioned = points.select(&:positioned?)
        started = points.filter_map(&:time).min
        puts "  creator: #{track.creator.inspect}; points: #{track.points_count}; " \
             "segments: #{track.segments.size}; laps: #{track.laps.size}"
        puts "  FIT signal: #{track.activity_signals.map(&:value).join(', ').inspect}"
        puts "  start: #{started&.utc&.iso8601}; listed: #{activity.started_at&.utc&.iso8601}"
        if started && activity.started_at
          puts "  listed − FIT start: #{((activity.started_at - started) / 60).round} min"
        end
        if positioned.any?
          longitudes = positioned.map(&:longitude)
          latitudes = positioned.map(&:latitude)
          puts format("  bounds: lon %.4f..%.4f, lat %.4f..%.4f; first point %.5f, %.5f",
                      longitudes.min, longitudes.max, latitudes.min, latitudes.max,
                      positioned.first.longitude, positioned.first.latitude)
        else
          puts "  no position: an indoor recording"
        end
        detection = Allure::ActivityDetector.new.detect(track)
        puts "  detected sport: #{detection&.sport_slug.inspect} (#{detection&.source.inspect})"
        puts "  platform: #{Allure::Virtual::Platforms.for_creator(track.creator)&.key.inspect} " \
             "(Zwift is not catalogued yet)"
        puts "  world id from the list: #{activity.world_id.inspect}"
      end
    end

    save.call(tokens, client.player_id, http.user_agent)
    puts "\nProbe succeeded."
  rescue Allure::Zwift::Error => error
    abort "\nProbe failed: #{error.class.name.demodulize}: #{error.message}"
  end
end
