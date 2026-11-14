# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"

RSpec.describe "Demo deployment configuration" do
  it "keeps deployment secrets out of Git and the Docker build context" do
    %w[.gitignore .dockerignore].each do |filename|
      expect(Rails.root.join(filename).read.lines.map(&:strip)).to include("/demo.env")
    end
  end

  it "refuses an unsafe shared operator while booting, before running any command" do
    _stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "test", "DEMO_INSTANCE" => "true", "DEMO_ACCOUNTS" => "tom,marie",
        "INSTANCE_OPERATOR_USERNAME" => "marie" },
      "bin/rails", "runner", "abort 'unsafe demo booted'", chdir: Rails.root
    )

    expect(status).not_to be_success
    expect(stderr).to include("DEMO_ACCOUNTS must not include INSTANCE_OPERATOR_USERNAME")
    expect(stderr).not_to include("unsafe demo booted")
  end

  it "refuses an operator without a stable password while booting" do
    _stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "test", "DEMO_INSTANCE" => "true", "DEMO_ACCOUNTS" => "tom",
        "INSTANCE_OPERATOR_USERNAME" => "marie", "DEMO_OPERATOR_PASSWORD" => nil },
      "bin/rails", "runner", "abort 'booted without an operator password'", chdir: Rails.root
    )

    expect(status).not_to be_success
    expect(stderr).to include("DEMO_OPERATOR_PASSWORD is required")
    expect(stderr).not_to include("booted without an operator password")
  end

  it "keeps the operator on by default and requires its password" do
    compose = YAML.load_file(Rails.root.join("docker-compose.demo.yml"), aliases: true)
    environment = compose.fetch("services").fetch("rails").fetch("environment")

    expect(environment.fetch("INSTANCE_OPERATOR_USERNAME")).to eq("${INSTANCE_OPERATOR_USERNAME:-marie}")
    expect(environment.fetch("DEMO_OPERATOR_PASSWORD"))
      .to eq("${DEMO_OPERATOR_PASSWORD:?DEMO_OPERATOR_PASSWORD is required}")
  end

  it "keeps federation off and waits for the server after seeding" do
    compose = YAML.load_file(Rails.root.join("docker-compose.demo.yml"), aliases: true)
    rails = compose.fetch("services").fetch("rails")

    expect(rails.fetch("environment").fetch("FEDERATION_ENABLED")).to eq("false")
    expect(rails.fetch("command")).to eq([ "bin/demo-boot" ])
    expect(rails.fetch("healthcheck").fetch("test").last).to include("http://127.0.0.1:3000/up")
    # Production only accepts APP_HOST, not the probe's loopback IP.
    expect(rails.fetch("healthcheck").fetch("test").last).to include("'Host' => ENV.fetch('APP_HOST')")
  end

  it "seeds from the demo image alone, with rails and worker on the same one" do
    compose = YAML.load_file(Rails.root.join("docker-compose.demo.yml"), aliases: true)
    services = compose.fetch("services")

    %w[rails worker].each do |name|
      expect(services.fetch(name).fetch("build").fetch("dockerfile")).to eq("Dockerfile.demo")
      expect(services.fetch(name).fetch("image")).to eq("${ALLURE_DEMO_IMAGE:-allure:demo}")
      expect(services.fetch(name).fetch("volumes")).to eq([ "allure_storage:/rails/storage" ])
    end
  end

  # The corpus is third-party data with no licence to redistribute, so the
  # demo image is built on the demo host and never pushed to a registry.
  it "never publishes the demo image" do
    Rails.root.glob(".github/workflows/*.yml").each do |config|
      expect(config.read).not_to include("demo-latest")
    end
  end

  it "only reports the database healthy once it accepts TCP, not during initdb" do
    compose = YAML.load_file(Rails.root.join("docker-compose.demo.yml"), aliases: true)
    db = compose.fetch("services").fetch("db")

    # Each reset re-runs initdb, whose temporary server only listens on the socket.
    expect(db.fetch("healthcheck").fetch("test").last).to include("pg_isready -h 127.0.0.1")
  end
end

# Execute the real wrapper in a disposable checkout, with Docker and the clock
# replaced by executables on PATH. No test can reach Docker or a live volume.
RSpec.describe "Demo nightly reset wrapper" do
  around do |example|
    Dir.mktmpdir("demo-deployment-", Rails.root.join("tmp")) do |directory|
      @sandbox = Pathname(directory)
      example.run
    end
  end

  let(:checkout) { @sandbox.join("checkout with spaces") }
  let(:fake_bin) { @sandbox.join("fake-bin") }
  let(:env_file) { @sandbox.join("demo config.env") }
  let(:docker_log) { @sandbox.join("docker.jsonl") }
  let(:state_directory) { checkout.join("tmp/demo-reset") }
  let(:stamp) { state_directory.join("last-success") }

  before do
    FileUtils.mkdir_p([ checkout.join("bin"), fake_bin ])
    FileUtils.cp(Rails.root.join("bin/demo-nightly-reset"), checkout.join("bin/demo-nightly-reset"))
    FileUtils.cp(Rails.root.join("docker-compose.demo.yml"), checkout.join("docker-compose.demo.yml"))
    env_file.write("DEMO_RESET_AT=03:00\nTZ=Europe/Paris\nDEMO_OPERATOR_PASSWORD=operator-password-2026\n")
    write_executable(fake_bin.join("date"), <<~'SH')
      #!/bin/sh
      printf '%s %s\n' "$TEST_TODAY" "$TEST_NOW"
    SH
    write_executable(fake_bin.join("docker"), <<~'RUBY')
      #!/usr/bin/env ruby
      require "json"
      File.open(ENV.fetch("DOCKER_LOG"), "a") do |log|
        log.puts(JSON.generate({ args: ARGV, directory: Dir.pwd, time_zone: ENV["TZ"] }))
      end
      exit 1 if ARGV.include?(ENV["FAIL_COMPOSE_ON"])
    RUBY
  end

  def write_executable(path, source)
    path.write(source)
    path.chmod(0o700)
  end

  def run_reset(now: "03:00", today: "2026-10-31", fail_on: nil, environment_file: env_file, directory: @sandbox)
    Open3.capture3(
      { "PATH" => "#{fake_bin}:#{ENV.fetch('PATH')}", "DOCKER_LOG" => docker_log.to_s,
        "TEST_TODAY" => today, "TEST_NOW" => now, "FAIL_COMPOSE_ON" => fail_on,
        "COMPOSE_PROJECT_NAME" => "allure-production", "COMPOSE_FILE" => "/not-the-demo.yml" },
      "bash", checkout.join("bin/demo-nightly-reset").to_s, environment_file.to_s, chdir: directory
    )
  end

  def docker_calls
    docker_log.file? ? docker_log.readlines.map { JSON.parse(it) } : []
  end

  it "pins the project and absolute paths regardless of the caller's directory or Compose environment" do
    _stdout, stderr, status = run_reset
    prefix = [ "compose", "--project-name", "allure-demo", "--project-directory", checkout.to_s,
               "--env-file", env_file.to_s, "--file", checkout.join("docker-compose.demo.yml").to_s ]

    expect(status).to be_success, stderr
    expect(docker_calls.map { it.fetch("args") }).to eq([
      [ *prefix, "config", "--quiet" ],
      [ *prefix, "down", "-v" ],
      [ *prefix, "up", "-d", "--pull", "never", "--wait", "--wait-timeout", "1800" ]
    ])
    expect(docker_calls.map { it.fetch("directory") }.uniq).to eq([ checkout.to_s ])
    expect(docker_calls.map { it.fetch("time_zone") }.uniq).to eq([ "Europe/Paris" ])
    expect(stamp.read.strip).to eq("2026-10-31")
  end

  it "accepts a relative env file without depending on Bash's source lookup path" do
    relative = Pathname("demo.env")
    FileUtils.cp(env_file, checkout.join(relative))

    _stdout, stderr, status = run_reset(environment_file: relative, directory: checkout)

    expect(status).to be_success, stderr
    expect(docker_calls.first.fetch("args")).to include(checkout.join(relative).to_s)
  end

  it "does nothing before the scheduled time" do
    _stdout, _stderr, status = run_reset(now: "02:59")

    expect(status).to be_success
    expect(docker_calls).to be_empty
    expect(stamp).not_to exist
  end

  it "catches up a missed schedule and records only one successful reset per day" do
    expect(run_reset(now: "04:10").last).to be_success
    expect(run_reset(now: "04:11").last).to be_success
    expect(docker_calls.length).to eq(3)

    expect(run_reset(today: "2026-11-01").last).to be_success
    expect(docker_calls.length).to eq(6)
    expect(stamp.read.strip).to eq("2026-11-01")
  end

  it "does not destroy anything when configuration validation fails" do
    _stdout, _stderr, status = run_reset(fail_on: "config")

    expect(status).not_to be_success
    expect(docker_calls.length).to eq(1)
    expect(docker_calls.first.fetch("args")).to include("config")
    expect(stamp).not_to exist
  end

  %w[down up].each do |command|
    it "releases its lock and retries after a failed #{command}, without marking the day successful" do
      expect(run_reset(fail_on: command).last).not_to be_success
      expect(stamp).not_to exist

      _stdout, stderr, status = run_reset(now: "03:01")

      expect(status).to be_success, stderr
      expect(stamp.read.strip).to eq("2026-10-31")
      expect(docker_calls.count { it.fetch("args").include?(command) }).to eq(2)
    end
  end

  it "does not overlap an in-progress reset" do
    FileUtils.mkdir_p(state_directory)
    File.open(state_directory.join("lock"), "w") do |lock|
      lock.flock(File::LOCK_EX)

      expect(run_reset.last).to be_success
      expect(docker_calls).to be_empty
      expect(stamp).not_to exist
    end
  end

  it "reports a lock failure rather than treating it as another running reset" do
    write_executable(fake_bin.join("flock"), "#!/bin/sh\nexit 2\n")

    _stdout, _stderr, status = run_reset

    expect(status.exitstatus).to eq(2)
    expect(docker_calls).to be_empty
    expect(stamp).not_to exist
  end

  it "rejects an invalid reset time without calling Docker" do
    env_file.write("DEMO_RESET_AT=25:00\n")

    _stdout, stderr, status = run_reset

    expect(status).not_to be_success
    expect(stderr).to include("DEMO_RESET_AT must be HH:MM")
    expect(docker_calls).to be_empty
  end

  it "rejects a missing env file without calling Docker" do
    _stdout, stderr, status = run_reset(environment_file: @sandbox.join("absent.env"))

    expect(status).not_to be_success
    expect(stderr).to include("no such env file")
    expect(docker_calls).to be_empty
  end

  it "refuses an operator without a password before destroying anything" do
    env_file.write("DEMO_RESET_AT=03:00\nTZ=Europe/Paris\n")

    _stdout, stderr, status = run_reset

    expect(status).not_to be_success
    expect(stderr).to include("DEMO_OPERATOR_PASSWORD is required")
    expect(docker_calls).to be_empty
    expect(stamp).not_to exist
  end

  it "refuses a short operator password before destroying anything" do
    env_file.write("DEMO_RESET_AT=03:00\nTZ=Europe/Paris\nDEMO_OPERATOR_PASSWORD=too-short\n")

    _stdout, stderr, status = run_reset

    expect(status).not_to be_success
    expect(stderr).to include("at least 15 characters")
    expect(docker_calls).to be_empty
  end

  it "refuses the shared password as the operator's before destroying anything" do
    env_file.write("DEMO_RESET_AT=03:00\nTZ=Europe/Paris\nDEMO_PASSWORD=shared-password-2026\n" \
                   "DEMO_OPERATOR_PASSWORD=shared-password-2026\n")

    _stdout, stderr, status = run_reset

    expect(status).not_to be_success
    expect(stderr).to include("must differ from DEMO_PASSWORD")
    expect(docker_calls).to be_empty
  end

  it "refuses the public development password as the operator's before destroying anything" do
    env_file.write("DEMO_RESET_AT=03:00\nTZ=Europe/Paris\nDEMO_OPERATOR_PASSWORD=allure-dev-password\n")

    _stdout, stderr, status = run_reset

    expect(status).not_to be_success
    expect(stderr).to include("public development password")
    expect(docker_calls).to be_empty
  end
end
