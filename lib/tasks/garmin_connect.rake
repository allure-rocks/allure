# frozen_string_literal: true

namespace :garmin_connect do
  # Feasibility check for docs/dev/REMOTE-IMPORTS.md against a real account,
  # from the network this command runs on. Writes nothing to the database and
  # never prints the password, the tokens or the cookies.
  #
  #   dip rails garmin_connect:probe
  #   GARMIN_EMAIL=… GARMIN_REGION=cn DOWNLOAD=1 dip rails garmin_connect:probe
  #
  # Garmin limits SSO sign-ins per account and address (HTTP 429). With
  # TOKEN_FILE=tmp/garmin-probe.json the DI token is kept in that file (mode
  # 0600, development only, delete it afterwards) and later runs skip the
  # sign-in; the rotated refresh token is written back after every refresh.
  desc "Sign in to Garmin Connect with the unofficial mobile flow and report each step (nothing stored)"
  task probe: :environment do
    require "io/console"
    require "tempfile"

    gc = Allure::GarminConnect
    step = ->(label) { puts "\n== #{label}" }
    timer = ->(&block) {
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      value = block.call
      [ value, format("%.1fs", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) ]
    }

    region = gc::Region.new(ENV.fetch("GARMIN_REGION", "com"))
    token_file = ENV["TOKEN_FILE"].presence&.then { Rails.root.join(it) }
    save_token = lambda do |token|
      next unless token_file

      File.write(token_file, JSON.generate(token.to_h.merge(region: region.key)), perm: 0o600)
      File.chmod(0o600, token_file)
    end
    di = gc::DiToken.new(region:)

    if token_file&.exist?
      step.call("Reusing the token stored in #{token_file.relative_path_from(Rails.root)} (no sign-in)")
      token = gc::DiToken::Token.from_h(JSON.parse(token_file.read))
      puts "  client_id: #{token.client_id}; expires_at: #{token.expires_at&.utc || 'unknown'}"
    else
      email = ENV["GARMIN_EMAIL"].presence || (print("Garmin e-mail: ") || STDIN.gets&.chomp).to_s
      password = ENV["GARMIN_PASSWORD"].presence || STDIN.getpass("Garmin password: ")
      abort "An e-mail and a password are required." if email.blank? || password.blank?

      step.call("Sign-in (#{region.domain}): mobile, then portal with a 10–20 s pause")
      sso = gc::Sso.new(region:)
      begin
        result, took = timer.call { sso.sign_in(email:, password:) }
      ensure
        password = nil
        sso.attempts.each { |attempt| puts "  #{attempt.strategy}: #{attempt.outcome}" }
      end

      if result.is_a?(gc::Sso::MfaRequired)
        step.call("Verification code required (#{result.method}, #{result.flow} flow)")
        code = STDIN.getpass("Code: ")
        result, took = timer.call { sso.verify_mfa(state: result.to_h, code:) }
      end
      puts "  ticket obtained through #{result.strategy} in #{took}"

      step.call("DI token exchange")
      token = di.exchange(ticket: result.ticket, service_url: result.service_url)
      save_token.call(token)
      puts "  client_id: #{token.client_id}"
      puts "  expires_at: #{token.expires_at&.utc || 'unknown'}; refresh token: #{token.refresh_token.present? ? 'yes' : 'no'}"
    end

    step.call("API: social profile")
    client = gc::Client.new(token:, region:, di_token: di)
    profile = client.social_profile
    save_token.call(client.token)
    puts "  profileId: #{profile['profileId']}, fullName present: #{profile['fullName'].present?}"

    step.call("DI token refresh (diauth only, no SSO)")
    refreshed = di.refresh(client.token)
    save_token.call(refreshed)
    puts "  refreshed; expires_at: #{refreshed.expires_at&.utc || 'unknown'}; " \
         "refresh token rotated: #{refreshed.refresh_token != client.token.refresh_token}"
    client = gc::Client.new(token: refreshed, region:, di_token: di)

    step.call("API: last 5 activities")
    activities = Array(client.activities(limit: 5))
    activities.each do |activity|
      puts format("  %-12s %-20s %-22s polyline=%-5s manual=%s",
                  activity["activityId"], activity["startTimeGMT"],
                  activity.dig("activityType", "typeKey"), activity["hasPolyline"], activity["manualActivity"])
    end
    puts "  (none)" if activities.empty?

    if ENV["DOWNLOAD"].present? && (activity = activities.find { |item| item["hasPolyline"] && !item["manualActivity"] })
      step.call("Original download of #{activity['activityId']}")
      Tempfile.create([ "garmin-probe", ".zip" ], binmode: true) do |file|
        client.download_original(activity["activityId"], io: file)
        names = []
        begin
          Workouts::ArchiveReader.new.each_manifest_entry(file, filename: "#{activity['activityId']}.zip") do |entry|
            names << entry.name
          end
        rescue StandardError => error
          names << "unreadable (#{error.class.name})"
        end
        puts "  #{file.size} bytes; track entries: #{names.presence&.join(', ') || 'none'}"
      end
    end
    save_token.call(client.token)

    puts "\nProbe succeeded."
  rescue Allure::GarminConnect::Error => error
    abort "\nProbe failed: #{error.class.name.demodulize}: #{error.message}"
  end

  # Development only, until the card's sign-in form exists
  # (docs/dev/REMOTE-IMPORTS.md): links an account with the DI token a probe
  # kept, without signing in to Garmin again. The token moves into the
  # connection's encrypted credentials and the file is deleted, because the
  # connection's first refresh spends the refresh token it holds.
  #
  #   USERNAME=marie dip rails garmin_connect:link_from_probe
  desc "Development: link an account to Garmin Connect with the token kept by garmin_connect:probe"
  task link_from_probe: :environment do
    abort "Development only." unless Rails.env.development?

    user = User.find_by(username: ENV.fetch("USERNAME", "marie"))
    abort "No such account." unless user
    file = Rails.root.join(ENV.fetch("TOKEN_FILE", "tmp/garmin-probe.json"))
    abort "#{file.relative_path_from(Rails.root)} does not exist: run the probe with TOKEN_FILE first." unless file.exist?

    stored = JSON.parse(file.read)
    token = Allure::GarminConnect::DiToken::Token.from_h(stored)
    connection = ImportConnection.for(user, "garmin_connect")
    connection.update!(
      status: "linked", region: stored.fetch("region", "com"), linked_at: Time.current, revoked_at: nil,
      pending_expires_at: nil, last_sync_error: nil,
      credentials: { "di_token" => token.access_token, "di_refresh_token" => token.refresh_token,
                     "di_client_id" => token.client_id },
      token_expires_at: token.expires_at
    )
    file.delete

    profile = ImportConnections::Providers.for(connection).profile
    connection.update!(external_account_id: profile["profileId"].to_s,
                       external_account_name: profile["fullName"].presence || user.username)
    puts "Linked @#{user.username} to Garmin Connect (#{connection.external_account_name}, profile #{connection.external_account_id})."
  rescue Allure::RemoteImports::Error => error
    connection&.update!(status: "expired", credentials: {}, token_expires_at: nil, last_sync_error: error.message)
    abort "Garmin refused the stored token (#{error.class.name.demodulize}: #{error.message}); run the probe again."
  end

  # Imports an account's Garmin Connect activities over a date range through
  # the remote batch pipeline, the task form of the card's « Récupérer des
  # activités… » (docs/dev/REMOTE-IMPORTS.md), processed by the
  # `remote_imports` worker.
  #
  #   USERNAME=marie FROM=2026-08-01 TO=2026-10-09 [SPORT=cycling] dip rails garmin_connect:retrieve
  desc "Import an account's Garmin Connect activities over FROM..TO (dates)"
  task retrieve: :environment do
    user = User.find_by(username: ENV.fetch("USERNAME", "marie"))
    abort "No such account." unless user
    connection = user.import_connections.find_by(provider: "garmin_connect")
    abort "@#{user.username} has no linked Garmin Connect account." unless connection&.linked?
    abort "Garmin Connect is disabled: set GARMIN_CONNECT_IMPORT_ENABLED=true." unless connection.enabled?

    range_to = ENV.fetch("TO", Date.current.iso8601)
    range_from = ENV.fetch("FROM") { (Date.iso8601(range_to) - 30).iso8601 }
    sport = ENV["SPORT"].presence && Sport.find_by!(slug: ENV["SPORT"])

    result = ImportConnections::Retrieval.new(connection:, from: range_from, to: range_to, sport:).call
    abort result.error unless result.success?

    batch = result.batch
    path = Rails.application.routes.url_helpers.workout_import_path(batch)
    puts "Batch #{batch.id} queued on remote_imports for #{batch.range_from}..#{batch.range_to}: #{path}"
  rescue Date::Error
    abort "FROM and TO must be dates (YYYY-MM-DD)."
  end
end
