# frozen_string_literal: true

module Demo
  # The seed half of the nightly reset (PLAN_DEMO.md §5). The database itself
  # is recreated by the host (`docker compose down -v && up -d`); this service
  # re-seeds the demo dataset with every date re-anchored on the present. It
  # never wipes anything — find-before-create makes a mid-day re-run harmless —
  # and it refuses to run at all outside demo mode, so an ordinary instance
  # cannot seed demo accounts by mistake.
  class Reset
    class NotDemoInstance < StandardError; end
    class MissingSeedFiles < StandardError; end

    SEED_FILES = %w[db/seeds/demo/seeder.rb db/seeds/demo/datasets.rb].freeze

    # `manifest:`/`anchors:` let the specs drive a tiny manifest; production
    # reads DEMO_DATASET like db/seeds/development.rb does.
    def initialize(manifest: nil, anchors: nil, out: $stdout)
      @manifest = manifest
      @anchors = anchors
      @out = out
    end

    def call
      raise NotDemoInstance, "DEMO_INSTANCE is not set" unless Allure::Demo.enabled?

      Allure::Demo.validate!
      require_seed_files
      validate_operator_password!
      dataset = DemoSeed::Datasets.fetch(ENV.fetch("DEMO_DATASET", "full")) unless @manifest && @anchors
      manifest = @manifest || dataset.manifest
      dating = DemoSeed::Dating.near_present(
        anchors: @anchors || dataset.anchors,
        usernames: manifest.fetch(:accounts).map { |account| account.fetch(:username) }
      )
      summary = DemoSeed::Runner.new(
        manifest:,
        corpus_root: Rails.root.join("references_apps/fit-test-files"),
        fixtures_root: Rails.root.join("spec/fixtures"),
        out: @out,
        file_time_shift: dating.file_shift,
        manual_time_shift: dating.manual_shift,
        # The demo's accounts sign in with a password alone (PLAN_DEMO.md §3).
        enrol_second_factor: false,
        password_for:
      ).call
      settle_notifications
      randomize_session_ids
      summary
    end

    private

    # The seed's social steps leave every notification unread; a demo visitor
    # should find a quiet bell, not a wall of red (PLAN_DEMO.md §3). Only the
    # published accounts' newest few stay unread.
    UNREAD_NOTIFICATIONS = 3

    def settle_notifications
      keep = User.where(username: Allure::Demo.accounts).flat_map do |user|
        user.notifications.order(created_at: :desc, id: :desc).limit(UNREAD_NOTIFICATIONS).ids
      end
      Notification.where.not(id: keep).update_all(read_at: Time.current)
    end

    # The published accounts keep the shared password (DEMO_PASSWORD, the
    # value the sign-in page displays); the configured operator keeps its
    # stable DEMO_OPERATOR_PASSWORD so the console survives the nightly reset;
    # every other background persona gets a fresh random one, so the
    # repository's public development constant opens no door on a demo
    # (PLAN_DEMO.md §3).
    def password_for
      shared = Allure::Demo.accounts
      published = ENV.fetch("DEMO_PASSWORD", "").presence || DemoSeed::PASSWORD
      operator = Allure::Demo.operator_username
      operator_password = Allure::Demo.operator_password
      lambda do |username|
        if shared.include?(username)
          published
        elsif username == operator && operator_password.present?
          operator_password
        else
          SecureRandom.base58(24)
        end
      end
    end

    # The seed files define the public development constant; the boot check
    # cannot know it, so the reset refuses it as the operator's password here.
    def validate_operator_password!
      return if Allure::Demo.operator_username.blank?

      password = Allure::Demo.operator_password
      return if password.blank?
      return unless password == DemoSeed::PASSWORD

      raise Allure::Demo::InvalidConfiguration,
            "DEMO_OPERATOR_PASSWORD must not be the public development password"
    end

    # The seed files ship in the demo image (Dockerfile.demo) only, never in
    # the production one; a clear refusal beats a confusing LoadError.
    def require_seed_files
      SEED_FILES.each do |relative|
        path = Rails.root.join(relative)
        raise MissingSeedFiles, "missing #{relative}: run the demo image (Dockerfile.demo)" unless path.file?

        require path.to_s
      end
    end

    # A fresh database hands out session ids from 1 again, and yesterday's
    # signed cookie would resume tomorrow's stranger (PLAN_DEMO.md §5). The
    # sequence starts at a random offset instead — only while the table is
    # empty, so a mid-day re-run never collides with live sessions.
    def randomize_session_ids
      return if ActiveRecord::Base.connection.select_value("SELECT 1 FROM sessions LIMIT 1").present?

      offset = SecureRandom.random_number(1_000_000_000) + 10_000_000
      ActiveRecord::Base.connection.exec_query(
        "SELECT setval('sessions_id_seq', $1, false)",
        "Demo session id offset",
        [ ActiveRecord::Relation::QueryAttribute.new("offset", offset, ActiveModel::Type::BigInteger.new) ]
      )
    end
  end
end
