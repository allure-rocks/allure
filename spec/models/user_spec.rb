# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "username" do
    it "normalizes usernames to lowercase" do
      expect(build(:user, username: " Marie_02 ").username).to eq("marie_02")
    end

    it "accepts letters, digits and underscores" do
      expect(build(:user, username: "marie_02")).to be_valid
    end

    it "rejects characters that would need escaping in a URI" do
      %w[marie\ dufour marie.dufour marie/dufour marie@dufour marié].each do |bad|
        expect(build(:user, username: bad)).not_to be_valid, "expected #{bad.inspect} to be rejected"
      end
    end

    it "reserves the configured operator name for console creation only" do
      allow(ENV).to receive(:fetch).with("INSTANCE_OPERATOR_USERNAME", "").and_return("ops")
      allow(ENV).to receive(:fetch).with("INSTANCE_NAME", "").and_return("")

      candidate = build(:user, username: "ops")
      expect(candidate.valid?(:self_registration)).to be(false)
      expect(candidate.errors.details[:username]).to include(error: :reserved)
      expect(candidate).to be_valid
      expect(build(:user, username: "rider")).to be_valid(:self_registration)
    end

    it "reserves the instance's own name for self-registration only" do
      allow(Allure::Instance).to receive(:name).and_return("Mon Club")

      candidate = build(:user, username: "mon_club")
      expect(candidate.valid?(:self_registration)).to be(false)
      expect(candidate.errors.details[:username]).to include(error: :reserved)
      expect(candidate).to be_valid
      expect(build(:user, username: "club_rider")).to be_valid(:self_registration)
    end

    it "rejects usernames longer than 30 characters" do
      expect(build(:user, username: "a" * 31)).not_to be_valid
    end

    # @Marie and @marie must never be two actors: WebFinger lookups and inbound
    # activity addressing are case-insensitive in practice, so a case-only
    # difference would make delivery ambiguous.
    it "is unique regardless of case" do
      create(:user, username: "marie")
      expect(build(:user, username: "MARIE")).not_to be_valid
    end

    # A live owner is a uniqueness collision, not a retirement: only the
    # tombstoned actor left by a deleted account reserves its name forever.
    it "reports a live owner as taken, never retired" do
      incumbent = create(:user, username: "marie")
      Federation::ActorProvisioner.new(user: incumbent).call!

      candidate = build(:user, username: "marie")
      candidate.valid?

      expect(candidate.errors.details[:username]).to include(hash_including(error: :taken))
      expect(candidate.errors.details[:username]).not_to include(hash_including(error: :retired))
    end

    it "cannot be changed after creation" do
      user = create(:user)

      expect(user.update(username: "different_name")).to be(false)
      expect(user.errors.of_kind?(:username, :immutable)).to be(true)
    end

    it "rejects every reserved name at creation" do
      User::RESERVED_USERNAMES.each do |reserved|
        candidate = build(:user, username: reserved)

        expect(candidate).not_to be_valid, "expected #{reserved} to be reserved"
        expect(candidate.errors.details[:username]).to include(hash_including(error: :exclusion))
      end
    end

    it "keeps the reserved list usable" do
      expect(User::RESERVED_USERNAMES).to eq(User::RESERVED_USERNAMES.uniq)
      User::RESERVED_USERNAMES.each do |reserved|
        expect(reserved).to match(User::USERNAME_FORMAT), "expected #{reserved.inspect} to be a valid username"
      end
    end

    # A release may reserve a name an existing account already holds: that
    # account must keep saving (its username is immutable anyway), so the
    # reservation only ever blocks creation. The row is inserted outside the
    # model, as the pre-release database would hold it.
    it "keeps an account whose name is now reserved updatable" do
      User.insert_all!([ {
        email_address: "legacy@allure.test",
        password_digest: "not-a-password",
        username: "www",
        locale: "fr",
        theme: "light",
        time_zone: "Europe/Paris",
        unit_system: "metric",
        avatar_seed: 1,
        created_at: Time.current,
        updated_at: Time.current
      } ])

      legacy = User.find_by!(username: "www")
      expect(legacy.update(theme: "dark")).to be(true)
      expect(legacy.reload.theme).to eq("dark")
    end

    it "is enforced by the database, not only by the model" do
      expect {
        User.insert_all!([ {
          email_address: "invalid-format@example.test",
          password_digest: "not-a-password",
          username: "not valid",
          locale: "fr",
          theme: "light",
          time_zone: "Europe/Paris",
          unit_system: "metric",
          avatar_seed: 1,
          created_at: Time.current,
          updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::StatementInvalid, /users_username_format/)
    end

    it "cannot be changed through a direct database update" do
      user = create(:user)

      expect {
        user.update_column(:username, "different_name")
      }.to raise_error(ActiveRecord::StatementInvalid, /username is immutable/)
    end
  end

  describe "credentials" do
    it "normalizes the email address to lowercase without surrounding space" do
      expect(build(:user, email_address: " Marie@Allure.Test ").email_address).to eq("marie@allure.test")
    end

    it "requires an email address" do
      expect(build(:user, email_address: "")).not_to be_valid

      user = build(:user, email_address: nil)
      user.valid?
      expect(user.errors.of_kind?(:email_address, :blank)).to be(true)
    end

    it "rejects malformed email addresses" do
      [ "not-an-email", "missing@", "@missing.test", "two@@allure.test" ].each do |bad|
        expect(build(:user, email_address: bad)).not_to be_valid, "expected #{bad.inspect} to be rejected"
      end
    end

    it "accepts plus-addressed mailboxes" do
      expect(build(:user, email_address: "marie+allure@allure.test")).to be_valid
    end

    it "rejects an address already in use regardless of case" do
      create(:user, email_address: "marie@allure.test")
      expect(build(:user, email_address: "MARIE@allure.test")).not_to be_valid
    end

    it "requires the NIST single-factor password length" do
      short = "a" * (described_class::MINIMUM_PASSWORD_LENGTH - 1)
      user = build(:user, password: short, password_confirmation: short)

      expect(user).not_to be_valid
      expect(user.errors.of_kind?(:password, :too_short)).to be(true)
    end

    it "accepts a password at the minimum length" do
      password = "a" * described_class::MINIMUM_PASSWORD_LENGTH
      expect(build(:user, password:, password_confirmation: password)).to be_valid
    end

    it "does not re-validate an existing password on unrelated updates" do
      password = "a" * described_class::MINIMUM_PASSWORD_LENGTH
      user = create(:user, password:, password_confirmation: password)

      expect(user.update(display_name: "Renamed")).to be(true)
    end
  end

  describe "presentation" do
    it "defaults both profile-sharing audiences to none in the database" do
      %w[profile_statistics_audience profile_records_audience].each do |attribute|
        column = described_class.columns_hash.fetch(attribute)
        expect(column.default).to eq("none")
        expect(column.null).to be(false)
        expect(described_class.new.public_send(attribute)).to eq("none")
      end
    end

    it "requires a known audience for each profile-sharing permission" do
      user = build(:user, profile_statistics_audience: nil, profile_records_audience: "public")
      expect(user).not_to be_valid
      expect(user.errors.of_kind?(:profile_statistics_audience, :inclusion)).to be(true)
      expect(user.errors.of_kind?(:profile_records_audience, :inclusion)).to be(true)
    end

    it "accepts independent profile-sharing audiences" do
      User::PROFILE_SHARING_AUDIENCES.product(User::PROFILE_SHARING_AUDIENCES).each do |statistics, records|
        expect(build(:user, profile_statistics_audience: statistics, profile_records_audience: records)).to be_valid
      end
    end

    it "also refuses unknown profile-sharing audiences in the database" do
      user = create(:user)
      %i[profile_statistics_audience profile_records_audience].each do |attribute|
        expect do
          described_class.transaction(requires_new: true) { user.update_column(attribute, "public") }
        end.to raise_error(ActiveRecord::StatementInvalid, /users_#{attribute}/)
      end
    end

    it "falls back to the username when no display name is set" do
      expect(build(:user, username: "marie", display_name: nil).display_name).to eq("marie")
    end

    it "assigns a random persisted avatar seed at creation" do
      user = create(:user)

      expect(user[:avatar_seed]).to be_a(Integer)
      expect(user[:avatar_seed]).to be_between(0, (2**31) - 1)
      expect(user.reload.avatar_seed).to eq(user[:avatar_seed])
    end

    it "derives a stable fallback seed for an unsaved account" do
      expect(build(:user, username: "marie").avatar_seed).to eq(build(:user, username: "marie").avatar_seed)
      expect(build(:user, username: "marie").avatar_seed).not_to eq(build(:user, username: "paul").avatar_seed)
    end
  end

  describe "federated identity" do
    subject(:user) { build(:user, username: "marie") }

    around do |example|
      previous = Allure::Federation.config
      Allure::Federation.config = Allure::Federation::Config.new(
        base_url: "https://allure.example",
        protocol: "https"
      )
      example.run
      Allure::Federation.config = previous
    end

    it "derives the actor URI from the configured base URL" do
      expect(user.actor_uri).to eq("https://allure.example/users/marie")
    end

    it "derives the handle" do
      expect(user.handle).to eq("marie@allure.example")
    end

    it "derives the key id" do
      expect(user.key_id).to eq("https://allure.example/users/marie#main-key")
    end

    # Storing these would let a row drift out of sync with FEDERATION_BASE_URL
    # and emit actor URIs the instance cannot actually serve.
    it "does not persist them" do
      expect(described_class.column_names).not_to include("actor_uri", "handle", "key_id")
    end

    it "has one persisted actor association" do
      expect(user).to respond_to(:actor)
    end
  end

  describe "preferences" do
    it "defaults to the instance's primary language" do
      expect(described_class.new.locale).to eq("fr")
    end

    it "rejects an unsupported locale" do
      expect(build(:user, locale: "pt")).not_to be_valid
    end

    it "rejects an unknown theme" do
      expect(build(:user, theme: "solarized")).not_to be_valid
    end

    it "accepts IANA time zones and rejects presentation labels" do
      expect(build(:user, time_zone: "America/New_York")).to be_valid
      expect(build(:user, time_zone: "Eastern Time (US & Canada)")).not_to be_valid
    end

    it "localizes invalid time-zone errors" do
      user = build(:user, time_zone: "Eastern Time (US & Canada)")
      user.validate

      expect(user.errors.full_messages_for(:time_zone)).to eq([ "Fuseau horaire n'est pas un fuseau horaire IANA valide" ])
    end

    it "defaults week start to Monday and rejects unknown values" do
      expect(described_class.new.week_start).to eq("monday")
      expect(build(:user, week_start: "saturday")).not_to be_valid
    end

    it "defaults the leaderboard category to unspecified and rejects unknown values" do
      expect(described_class.new.leaderboard_category).to eq("unspecified")
      expect(build(:user, leaderboard_category: "women")).to be_valid
      expect(build(:user, leaderboard_category: "female")).not_to be_valid
    end

    it "enforces the leaderboard category in the database" do
      user = create(:user)

      expect { user.update_column(:leaderboard_category, "other") }.to raise_error(ActiveRecord::StatementInvalid, /users_leaderboard_category/)
    end

    it "defaults track smoothing off at the medium level and rejects unknown levels" do
      expect(described_class.new.smooth_tracks).to be(false)
      expect(described_class.new.track_smoothing_level).to eq("medium")
      expect(build(:user, track_smoothing_level: "extreme")).not_to be_valid
      expect(build(:user, smooth_tracks: nil)).not_to be_valid
    end

    it "defaults route images to the device appearance and rejects unknown themes" do
      expect(described_class.new.route_image_theme).to eq("auto")
      expect(build(:user, route_image_theme: "dark")).to be_valid
      expect(build(:user, route_image_theme: "sepia")).not_to be_valid
      expect(build(:user, route_image_theme: nil)).not_to be_valid
    end

    it "limits display name and biography length" do
      expect(build(:user, display_name: "x" * 61)).not_to be_valid
      expect(build(:user, bio: "x" * 1001)).not_to be_valid
      expect(build(:user, display_name: "", bio: "")).to be_valid
    end

    it "opts out of Gravatar by default" do
      expect(described_class.new.gravatar_opt_in).to be(false)
      expect(build(:user, gravatar_opt_in: nil)).not_to be_valid
    end

    it "opts out of terrain elevation by default" do
      expect(described_class.new.elevation_enrichment_enabled).to be(false)
      expect(build(:user, elevation_enrichment_enabled: nil)).not_to be_valid
    end

    it "keeps a curated pink avatar palette" do
      expect(described_class::AVATAR_PALETTE).to all(match(/\A#[0-9a-f]{6}\z/))
    end

    it "reports no avatar image before an upload or cached Gravatar" do
      expect(build(:user).avatar_image?).to be(false)
      expect(build(:user).avatar_source).to be_nil
    end

    it "prefers an uploaded avatar over a cached Gravatar" do
      user = create(:user, gravatar_opt_in: true)
      user.gravatar_cache.attach(io: StringIO.new("cached"), filename: "gravatar.jpg", content_type: "image/jpeg")
      user.avatar.attach(io: StringIO.new("uploaded"), filename: "avatar.webp", content_type: "image/webp")

      expect(user.avatar_image?).to be(true)
      expect(user.avatar_source.name).to eq("avatar")
    end

    it "is the operator only for the configured username" do
      user = build(:user, username: "marie")

      allow(ENV).to receive(:fetch).with("INSTANCE_OPERATOR_USERNAME", "").and_return("MARIE")
      expect(user.instance_operator?).to be(true)

      allow(ENV).to receive(:fetch).with("INSTANCE_OPERATOR_USERNAME", "").and_return("")
      expect(user.instance_operator?).to be(false)

      allow(ENV).to receive(:fetch).with("INSTANCE_OPERATOR_USERNAME", "").and_return("paul")
      expect(user.instance_operator?).to be(false)
    end
  end

  describe "release notes marker" do
    it "marks the running release as seen for a new account" do
      expect(create(:user).release_notes_seen_version).to eq(Allure::VERSION)
    end

    it "keeps an explicit marker given at creation" do
      expect(create(:user, release_notes_seen_version: "0.0.1").release_notes_seen_version).to eq("0.0.1")
    end
  end

  describe "sport defaults" do
    it "accepts the generic itself and its curated variants" do
      cycling = catalog_sport("cycling")
      expect(build(:user, default_cycling_sport: cycling)).to be_valid
      expect(build(:user, default_cycling_sport: catalog_sport("cycling_road"))).to be_valid

      catalog_sport("running")
      expect(build(:user, default_running_sport: catalog_sport("trail"))).to be_valid
    end

    it "rejects a sport outside the curated list and an inactive variant" do
      catalog_sport("cycling")
      catalog_sport("running")
      # Tennis shares the running icon family but is not a running variant.
      expect(build(:user, default_running_sport: catalog_sport("tennis_outdoor"))).not_to be_valid
      expect(build(:user, default_cycling_sport: catalog_sport("running"))).not_to be_valid

      variant = catalog_sport("cycling_road")
      variant.update_column(:active, false)
      expect(build(:user, default_cycling_sport: variant)).not_to be_valid
    end

    it "resolves a preferred sport only for generic slugs" do
      catalog_sport("running")
      trail = catalog_sport("trail")
      user = build(:user, default_running_sport: trail)

      expect(user.preferred_sport_for("running")).to eq(trail)
      expect(user.preferred_sport_for("trail")).to be_nil
      expect(user.preferred_sport_for("cycling")).to be_nil
    end

    it "ignores an inactive target at read time" do
      catalog_sport("running")
      user = create(:user, default_running_sport: catalog_sport("trail"))
      Sport.where(slug: "trail").update_all(active: false)

      expect(user.reload.preferred_sport_for("running")).to be_nil
    end
  end
end
