# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublishingProfile do
  describe "audience and settings" do
    it "accepts the built-in public and followers profiles" do
      expect(build(:publishing_profile)).to be_valid
      expect(build(:publishing_profile, :followers)).to be_valid
    end

    it "allows only public custom profiles" do
      expect(build(:publishing_profile, :custom, audience: "public")).to be_valid
      expect(build(:publishing_profile, :custom, audience: "followers")).not_to be_valid
    end

    it "uses safe defaults when settings are omitted" do
      profile = build(:publishing_profile, settings: {})

      expect(profile).to be_valid
      expect(profile.settings).to eq(PublishingProfile::DEFAULT_SETTINGS)
      expect(profile.settings).to include("route" => true, "route_image" => true, "basemap" => true, "gpx" => false)
    end

    it "shares no heart rate in a new profile, while accepting it when ticked (PLAN_HEART_RATE.md D7)" do
      default = build(:publishing_profile, settings: {})
      default.validate

      expect(default.settings["metrics"]).not_to include("average_heart_rate", "max_heart_rate")
      expect(default.settings["metrics"]).to include("distance", "average_cadence", "average_power")
      expect(build(:publishing_profile, settings: { "metrics" => PublishingProfile::METRIC_KEYS })).to be_valid
    end

    it "groups every metric exactly once for the form" do
      expect(PublishingProfile::METRIC_GROUPS.values.flatten).to eq(PublishingProfile::METRIC_KEYS)
    end

    it "keeps an existing profile's heart-rate choice" do
      profile = create(:publishing_profile, settings: PublishingProfile::DEFAULT_SETTINGS.merge("metrics" => PublishingProfile::METRIC_KEYS))

      expect(profile.reload.settings["metrics"]).to include("average_heart_rate", "max_heart_rate")
    end

    it "accepts the basemap setting as a boolean" do
      expect(build(:publishing_profile, settings: PublishingProfile::DEFAULT_SETTINGS.merge("basemap" => false))).to be_valid
      expect(build(:publishing_profile, settings: PublishingProfile::DEFAULT_SETTINGS.merge("basemap" => "yes"))).not_to be_valid
    end

    it "keeps device sharing off by default and accepts it as a boolean" do
      default = build(:publishing_profile, settings: {})
      expect(default).to be_valid
      expect(default.settings).to include("device" => false)
      expect(build(:publishing_profile, settings: PublishingProfile::DEFAULT_SETTINGS.merge("device" => true))).to be_valid
      expect(build(:publishing_profile, settings: PublishingProfile::DEFAULT_SETTINGS.merge("device" => "yes"))).not_to be_valid
    end

    it "provisions built-in profiles with the sanitized route image on" do
      user = create(:user)

      PublishingProfile.ensure_built_ins_for!(user)

      expect(user.publishing_profiles.find_by!(built_in_key: "public").settings).to include("route_image" => true)
    end

    it "rejects unknown or unsafe settings" do
      expect(build(:publishing_profile, settings: { "coordinates" => true })).not_to be_valid
      expect(build(:publishing_profile, settings: { "metrics" => [ "private_notes" ] })).not_to be_valid
    end

    it "allows endpoint masking to be configured independently" do
      profile = build(
        :publishing_profile,
        settings: PublishingProfile::DEFAULT_SETTINGS.merge(
          "mask_start" => true,
          "mask_finish" => false
        )
      )

      expect(profile).to be_valid
    end

    it "keeps a built-in profile's audience fixed" do
      expect(build(:publishing_profile, built_in_key: "public", audience: "followers")).not_to be_valid
    end
  end

  describe "publishing delay" do
    it "defaults to immediate publishing" do
      profile = create(:publishing_profile)

      expect(profile.reload.publish_delay_seconds).to eq(0)
      expect(PublishingProfile::PUBLISH_DELAYS.fetch("immediate")).to eq(0)
    end

    it "accepts only the preset delays" do
      PublishingProfile::PUBLISH_DELAY_VALUES.each do |seconds|
        profile = build(:publishing_profile, publish_delay_seconds: seconds)
        expect(profile).to be_valid
      end

      expect(build(:publishing_profile, publish_delay_seconds: 3_600)).not_to be_valid
      expect(build(:publishing_profile, publish_delay_seconds: -1)).not_to be_valid
    end

    it "is policy, not a snapshot setting" do
      expect(PublishingProfile::SETTING_KEYS).not_to include("publish_delay_seconds")
    end
  end

  # docs/dev/FEDERATION.md: local followers read the followers audience whatever the
  # switches say; FEDERATION_RESTRICTED_ENABLED only gates its federation.
  describe "publishability" do
    %w[false true].each do |restricted|
      it "publishes the public and built-in followers profiles with restricted federation #{restricted}" do
        allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(restricted == "true")

        expect(build(:publishing_profile, :followers)).to be_publishable
        expect(build(:publishing_profile)).to be_publishable
        expect(build(:publishing_profile, :custom, audience: "public")).to be_publishable
        expect(build(:publishing_profile, :custom, audience: "followers")).not_to be_valid
      end
    end
  end

  describe "database invariants" do
    it "allows only one profile for each built-in key and owner" do
      user = create(:user)
      create(:publishing_profile, user:)

      expect { create(:publishing_profile, user:) }
        .to raise_error(ActiveRecord::RecordInvalid, /already been taken/)
    end

    it "allows multiple custom profiles for the same owner" do
      user = create(:user)

      expect { create(:publishing_profile, :custom, user:) }.not_to raise_error
      expect { create(:publishing_profile, :custom, user:) }.not_to raise_error
    end
  end

  describe "automatic publishing" do
    let(:user) { create(:user) }

    it "is off by default and needs the acknowledgement to turn on" do
      profile = create(:publishing_profile, user:)
      expect(profile.auto_publish).to be(false)

      profile.auto_publish = true
      expect(profile).not_to be_valid

      profile.auto_publish_acknowledged = true
      expect(profile).to be_valid
    end

    it "is allowed for the followers profile without restricted federation" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      profile = create(:publishing_profile, :followers, user:)

      profile.assign_attributes(auto_publish: true, auto_publish_acknowledged: true)

      expect(profile).to be_valid
    end

    it "keeps one automatic profile per audience, in the database too" do
      create(:publishing_profile, user:, auto_publish: true, auto_publish_acknowledged: true)
      other = create(:publishing_profile, :custom, user:)

      other.assign_attributes(auto_publish: true, auto_publish_acknowledged: true)
      expect(other).not_to be_valid
      expect { other.update_column(:auto_publish, true) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "excludes no sport by default, and stores the list sorted and unique" do
      catalog_sport("walking")
      catalog_sport("hiking")
      profile = create(:publishing_profile, user:)
      expect(profile.auto_publish_excluded_sports).to eq([])

      profile.update!(auto_publish_excluded_sports: [ "", "walking", "hiking", "walking" ])

      expect(profile.reload.auto_publish_excluded_sports).to eq(%w[hiking walking])
    end

    it "refuses a sport the catalog does not know" do
      profile = create(:publishing_profile, user:)
      profile.auto_publish_excluded_sports = [ "not_a_sport" ]

      expect(profile).not_to be_valid
      expect(profile.errors[:base]).to include(
        I18n.t("activerecord.errors.models.publishing_profile.attributes.base.auto_publish_excluded_sports_unknown")
      )
    end

    it "matches a workout's sport by slug, excluding none when the list is empty" do
      profile = create(:publishing_profile, user:)
      expect(profile.auto_publish_excludes_sport?(catalog_sport("walking"))).to be(false)

      profile.update!(auto_publish_excluded_sports: %w[walking])

      expect(profile.auto_publish_excludes_sport?(catalog_sport("walking"))).to be(true)
      expect(profile.auto_publish_excludes_sport?(catalog_sport("hiking"))).to be(false)
    end
  end
end
