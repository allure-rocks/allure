# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Publishing profiles" do
  let(:user) { create(:user) }

  def sign_in_user
    sign_in_as(user)
  end

  # DESIGN.md §19.13: the followers profile names who receives its
  # publications under the instance's switches.
  {
    [ false, false ] => "local",
    [ false, true ] => "local",
    [ true, false ] => "not_federated",
    [ true, true ] => "federated"
  }.each do |(federation, restricted), key|
    it "states the followers reach #{key} with federation #{federation} and restricted federation #{restricted}" do
      allow(Allure::Federation::Config).to receive_messages(enabled?: federation, restricted_enabled?: restricted)
      profile = create(:publishing_profile, :followers, user:)
      sign_in_user

      get publishing_profile_path(profile)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.followers_reach.#{key}")))
      expect(response.body).to include(edit_publishing_profile_path(profile))
    end
  end

  it "creates built-in profiles for the owner and lists them" do
    sign_in_user

    get publishing_profiles_path

    expect(response).to have_http_status(:ok)
    expect(user.publishing_profiles.where(built_in_key: %w[public followers]).count).to eq(2)
    expect(response.body).to include("Profil public", "Profil abonnés")
    followers = user.publishing_profiles.find_by!(built_in_key: "followers")
    expect(response.body).to include(edit_publishing_profile_path(followers))

    page = response.parsed_body
    expect(page.at_css("table.card-table")).to be_present
    expect(page.css("table tbody tr").length).to eq(2)
    public_profile = user.publishing_profiles.find_by!(built_in_key: "public")
    expect(page.at_css("a[href='#{publishing_profile_path(public_profile)}']")).to be_present
    expect(page.at_css("form[action='#{restore_defaults_publishing_profile_path(public_profile)}']")).to be_present
  end

  it "lists custom profiles with their edit and delete actions" do
    custom = create(:publishing_profile, :custom, user:, name: "Custom row")
    sign_in_user

    get publishing_profiles_path

    row = response.parsed_body.css("table tbody tr").find { |tr| tr.text.include?("Custom row") }
    expect(row).to be_present
    expect(row.at_css("a[href='#{edit_publishing_profile_path(custom)}']")).to be_present
    expect(row.at_css("form[action='#{publishing_profile_path(custom)}']")).to be_present
  end

  it "exposes and persists the records setting" do
    profile = create(:publishing_profile, :custom, user:)
    sign_in_user

    get edit_publishing_profile_path(profile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("publishing_profile[settings][records]")
    expect(response.body).to include(I18n.t("publishing_profiles.settings.records_hint"))

    patch publishing_profile_path(profile), params: {
      publishing_profile: { name: profile.name, audience: "public",
                            settings: profile.settings.merge("records" => "1") }
    }

    expect(profile.reload.settings["records"]).to be(true)
  end

  it "exposes and persists the device setting" do
    profile = create(:publishing_profile, :custom, user:)
    sign_in_user

    get edit_publishing_profile_path(profile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("publishing_profile[settings][device]")
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.settings.device_hint")))

    patch publishing_profile_path(profile), params: {
      publishing_profile: { name: profile.name, audience: "public",
                            settings: profile.settings.merge("device" => "1") }
    }

    expect(profile.reload.settings["device"]).to be(true)
  end

  # PLAN_COMMENTS.md §6.4: open by default, an older profile without the key
  # stays open, and an unchecked box is an explicit close.
  it "exposes the comments setting, open for an older profile, and stores an unchecked box as closed" do
    profile = create(:publishing_profile, :custom, user:)
    profile.update_column(:settings, profile.settings.except("comments"))
    sign_in_user

    get edit_publishing_profile_path(profile)

    checkbox = response.parsed_body.at_css("input[name='publishing_profile[settings][comments]']")
    expect(checkbox["checked"]).to be_present
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.settings.comments_hint")))

    patch publishing_profile_path(profile), params: {
      publishing_profile: { name: profile.name, audience: "public",
                            settings: profile.settings.except("comments").transform_values { |value| value == true ? "1" : value } }
    }

    expect(profile.reload.settings["comments"]).to be(false)
    expect(profile.settings["route"]).to be(true)

    get publishing_profile_path(profile)
    expect(response.parsed_body.text).to include("Commentaires", "Fermés")
  end

  it "exposes and persists the publishing delay" do
    profile = create(:publishing_profile, :custom, user:)
    sign_in_user

    get edit_publishing_profile_path(profile)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("publishing_profile[publish_delay_seconds]")
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.form.delay_hint")))
    PublishingProfile::PUBLISH_DELAYS.each_key do |key|
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.delays.#{key}")))
    end

    patch publishing_profile_path(profile), params: {
      publishing_profile: { name: profile.name, audience: "public", publish_delay_seconds: 604_800 }
    }

    expect(profile.reload.publish_delay_seconds).to eq(604_800)

    post restore_defaults_publishing_profile_path(profile)

    expect(profile.reload.publish_delay_seconds).to eq(0)
  end

  describe "automatic publishing" do
    let!(:profile) { create(:publishing_profile, user:) }

    def update_auto(**fields)
      patch publishing_profile_path(profile), params: { publishing_profile: { name: profile.name, audience: "public", **fields } }
    end

    it "explains the option, off by default, on the list and the form" do
      sign_in_user

      get publishing_profiles_path
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.auto_notice.off_title")))

      get edit_publishing_profile_path(profile)
      expect(response.body).to include("publishing_profile[auto_publish]", "publishing_profile[auto_publish_acknowledged]",
                                       "publishing_profile[auto_publish_excluded_sports][]")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.form.auto_irrevocable")))
      expect(profile.auto_publish).to be(false)
    end

    it "requires the acknowledgement to turn it on" do
      sign_in_user

      update_auto(auto_publish: "1")
      expect(response).to have_http_status(:unprocessable_content)
      expect(profile.reload.auto_publish).to be(false)

      update_auto(auto_publish: "1", auto_publish_acknowledged: "1", auto_publish_exclude_commute: "1")
      expect(profile.reload).to have_attributes(auto_publish: true, auto_publish_exclude_commute: true)

      # Already on: saving other settings needs no new acknowledgement.
      update_auto(auto_publish: "1", publish_delay_seconds: 86_400)
      expect(profile.reload).to have_attributes(auto_publish: true, publish_delay_seconds: 86_400)

      get publishing_profiles_path
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.auto_notice.on_title")))
      get new_workout_import_path
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("publishing_profiles.auto_notice.on_title")))

      profile.update!(auto_publish_excluded_sports: [ catalog_sport("walking").slug ])
      post restore_defaults_publishing_profile_path(profile)
      expect(profile.reload).to have_attributes(auto_publish: false, auto_publish_excluded_sports: [])
    end

    it "allows one automatic profile per audience" do
      create(:publishing_profile, :custom, user:, name: "Other", auto_publish: true, auto_publish_acknowledged: true)
      sign_in_user

      update_auto(auto_publish: "1", auto_publish_acknowledged: "1")

      expect(response).to have_http_status(:unprocessable_content)
      expect(profile.reload.auto_publish).to be(false)
    end

    it "excludes the chosen sports from automatic publishing" do
      catalog_sport("walking")
      catalog_sport("hiking")
      sign_in_user

      update_auto(auto_publish: "1", auto_publish_acknowledged: "1",
                  auto_publish_excluded_sports: [ "", "walking", "hiking" ])

      expect(profile.reload.auto_publish_excluded_sports).to eq(%w[hiking walking])

      get publishing_profiles_path
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("publishing_profiles.auto_notice.sports_excluded", sports: "Marche, Randonnée"))
      )
    end

    it "clears the sport exclusion list when every sport is unticked" do
      profile.update!(auto_publish_excluded_sports: [ catalog_sport("walking").slug ])
      sign_in_user

      update_auto(auto_publish_excluded_sports: [ "" ])

      expect(profile.reload.auto_publish_excluded_sports).to eq([])
    end
  end

  it "creates and updates a custom profile" do
    sign_in_user

    post publishing_profiles_path, params: {
      publishing_profile: {
        name: "Minimal public",
        audience: "public",
        settings: {
          title: "1",
          description: "0",
          route: "1",
          gpx: "0",
          route_image: "0",
          mask_start: "1",
          mask_finish: "0",
          metrics: [ "distance" ]
        }
      }
    }
    profile = user.publishing_profiles.find_by!(name: "Minimal public")

    expect(response).to redirect_to(publishing_profile_path(profile))
    expect(profile.settings).to include(
      "title" => true,
      "description" => false,
      "mask_start" => true,
      "mask_finish" => false,
      "metrics" => [ "distance" ]
    )

      patch publishing_profile_path(profile), params: {
        publishing_profile: {
          name: "Minimal public updated",
          audience: "public",
          settings: { title: "1", description: "1", route: "0", metrics: [] }
        }
      }

      expect(response).to redirect_to(publishing_profile_path(profile))
      expect(profile.reload).to have_attributes(name: "Minimal public updated", audience: "public")
      expect(profile.settings).to include("description" => true, "route" => false, "metrics" => [])
    end

    it "rejects followers as a custom audience" do
      sign_in_user

      post publishing_profiles_path, params: {
        publishing_profile: {
          name: "Followers custom",
          audience: "followers",
          settings: { title: "1", metrics: [ "distance" ] }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("activerecord.errors.models.publishing_profile.attributes.audience.followers_unavailable"))
      )
      expect(user.publishing_profiles.where(name: "Followers custom")).to be_empty
    end

    it "explains the reserved followers audience on the custom form" do
      sign_in_user

      get new_publishing_profile_path

      option = response.parsed_body.at_css(%(select[name="publishing_profile[audience]"] option[value="followers"]))
      expect(option["disabled"]).to eq("disabled")
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("publishing_profiles.form.audience_hint"))
      )
    end

    it "lets the owner edit the built-in followers profile whatever restricted federation says" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      profile = create(:publishing_profile, :followers, user:, settings: { "title" => false })
      sign_in_user

      post restore_defaults_publishing_profile_path(profile)

      expect(response).to redirect_to(publishing_profile_path(profile))
      expect(profile.reload).to have_attributes(audience: "followers", settings: PublishingProfile::DEFAULT_SETTINGS)
  end

  it "deletes custom profiles but keeps built-in profiles" do
    custom = create(:publishing_profile, :custom, user:)
    built_in = create(:publishing_profile, user:)
    sign_in_user

    delete publishing_profile_path(custom)
    expect(response).to redirect_to(publishing_profiles_path)
    expect(PublishingProfile).not_to exist(custom.id)

    delete publishing_profile_path(built_in)
    expect(response).to redirect_to(publishing_profiles_path)
    expect(PublishingProfile).to exist(built_in.id)
  end

  it "does not expose another user's profile" do
    profile = create(:publishing_profile)
    sign_in_user

    get publishing_profile_path(profile)

    expect(response).to have_http_status(:not_found)
  end

  it "does not mutate an existing publication when a profile changes" do
    workout = create(:workout, user:, title: "Snapshot title")
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :custom, :without_endpoint_masks, user:)
    publish_workout!(user:, workout:, profile:)
    publication = workout.reload.active_publications.first
    sign_in_user

    patch publishing_profile_path(profile), params: {
      publishing_profile: {
        name: profile.name,
        audience: "public",
        settings: { title: "0", metrics: [] }
      }
    }

    expect(response).to redirect_to(publishing_profile_path(profile))
    expect(publication.reload.profile_snapshot["settings"]["title"]).to be(true)
    expect(publication.profile_snapshot["settings"]["metrics"]).to include("distance")
  end

  it "keeps snapshot provenance when a profile is renamed" do
    workout = create(:workout, user:, title: "Snapshot title")
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :custom, :without_endpoint_masks, user:, name: "Original name")
    publish_workout!(user:, workout:, profile:)
    publication = workout.reload.active_publications.first
    expect(publication.profile_snapshot["name"]).to eq("Original name")
    sign_in_user

    patch publishing_profile_path(profile), params: {
      publishing_profile: { name: "Renamed", audience: "public", settings: profile.settings }
    }

    expect(response).to redirect_to(publishing_profile_path(profile))
    expect(publication.reload.profile_snapshot["name"]).to eq("Original name")

    get workout_path(workout)
    # After the rename the selector shows "Renamed", so "Original name" can only
    # come from the immutable snapshot provenance.
    expect(response.body).to include("Original name")
  end
end
