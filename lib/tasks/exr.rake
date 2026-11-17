# frozen_string_literal: true

namespace :exr do
  # Feasibility check for docs/dev/REMOTE-IMPORTS.md against a real EXR
  # account. Writes nothing to the database and never prints the password or
  # a cookie value.
  #
  #   dip rails exr:probe
  #   EXR_EMAIL=… DOWNLOAD=1 COOKIE_FILE=tmp/exr-probe.json dip rails exr:probe
  #
  # With COOKIE_FILE the remember cookie is kept in that file (mode 0600,
  # development only, delete it afterwards) and later runs skip the sign-in.
  desc "Sign in to the EXR account site and report each step (nothing stored)"
  task probe: :environment do
    require "io/console"
    require "tempfile"

    exr = Allure::Exr
    step = ->(label) { puts "\n== #{label}" }
    describe = lambda do |cookie|
      expiry = cookie.expires_at ? "#{cookie.expires_at.utc.iso8601} (#{((cookie.expires_at - Time.now) / 86_400).round} days)" : "session"
      "#{cookie.name.sub(/(remember_web_)\h+/, '\1…')} — expires #{expiry}"
    end
    cookie_file = ENV["COOKIE_FILE"].presence&.then { Rails.root.join(it) }
    save_cookie = lambda do |cookie|
      next unless cookie_file

      File.write(cookie_file, JSON.generate(name: cookie.name, value: cookie.value, expires_at: cookie.expires_at&.iso8601),
                 perm: 0o600)
      File.chmod(0o600, cookie_file)
    end

    if cookie_file&.exist?
      step.call("Reusing the remember cookie stored in #{cookie_file.relative_path_from(Rails.root)} (no sign-in)")
      stored = JSON.parse(cookie_file.read)
      remember = exr::Http::Cookie.new(name: stored.fetch("name"), value: stored.fetch("value"),
                                       expires_at: stored["expires_at"] && Time.iso8601(stored["expires_at"]))
      puts "  #{describe.call(remember)}"
    else
      email = ENV["EXR_EMAIL"].presence || (print("EXR e-mail: ") || STDIN.gets&.chomp).to_s
      password = ENV["EXR_PASSWORD"].presence || STDIN.getpass("EXR password: ")
      abort "An e-mail and a password are required." if email.blank? || password.blank?

      step.call("Sign-in (GET /login, POST /login without the remember checkbox)")
      session = exr::Session.new
      begin
        remember = session.sign_in(email:, password:)
      ensure
        password = nil
        session.http.cookies.each { |cookie| puts "  cookie #{describe.call(cookie)}" }
      end
      save_cookie.call(remember)
      puts "  remember cookie obtained"
    end

    step.call("Session list with the remember cookie alone")
    client = exr::Client.new(remember:, on_rotate: ->(cookie) {
      puts "  the site replaced the remember cookie"
      save_cookie.call(cookie)
    })
    first = client.page(1)
    puts "  page 1: #{first.rows.size} rows; next page: #{first.next_page.inspect}; last page: #{first.last_page}"
    first.rows.first(5).each do |row|
      puts format("  %s  %-19s  %8s m  %6s s  %s", row.uuid, row.listed_at&.strftime("%F %T"), row.distance_m&.round,
                  row.duration_s, row.title)
    end

    if first.next_page
      second = client.page(first.next_page)
      puts "  page #{first.next_page}: #{second.rows.size} rows; oldest listed #{second.rows.filter_map(&:listed_at).min&.strftime('%F %T')}"
    end
    twins = first.rows.group_by(&:listed_at).select { |_, rows| rows.size > 1 }
    puts "  sessions listed twice with the same start on page 1: #{twins.size}"

    if ENV["DOWNLOAD"].present? && (row = first.rows.first)
      step.call("FIT download of #{row.uuid}")
      Tempfile.create([ "exr-probe", ".fit" ], binmode: true) do |file|
        client.download_fit(row.uuid, io: file)
        puts "  #{file.size} bytes, FIT header present"
        track = Allure::Fit::Parser.new.parse(file)
        platform = Allure::Virtual::Platforms.for_creator(track.creator)
        started = track.segments.first&.first_point&.time
        puts "  creator: #{track.creator.inspect}; platform: #{platform&.key.inspect}; points: #{track.points_count}"
        if started && row.listed_at
          offset = ((row.listed_at - started.utc) / 60).round
          puts "  FIT start #{started.utc.iso8601}, listed #{row.listed_at.strftime('%F %T')} → listed = UTC #{format('%+d', offset)} min"
        end
      end
    end

    save_cookie.call(client.remember)
    puts "\nProbe succeeded."
  rescue Allure::Exr::Error => error
    abort "\nProbe failed: #{error.class.name.demodulize}: #{error.message}"
  end
end
