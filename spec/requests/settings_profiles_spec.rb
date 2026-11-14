# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings profiles" do
  let(:user) { create(:user) }

  def sign_in_as(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  def image_upload(width: 128, height: 128, format: ".png", content_type: "image/png")
    file = Tempfile.new([ "avatar", format ], binmode: true)
    Vips::Image.black(width, height).write_to_file(file.path)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: "avatar#{format}")
  end

  def text_upload
    file = Tempfile.new([ "avatar", ".txt" ], binmode: true)
    file.write("not an image")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/plain", true, original_filename: "avatar.txt")
  end

  it "requires authentication" do
    get settings_profile_path

    expect(response).to redirect_to(new_session_path)
  end

  it "shows the identity and avatar form to the owner" do
    sign_in_as

    get settings_profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("settings.profile.display_name"))
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.profile.avatar_upload")))
    expect(response.body).to include(ERB::Util.html_escape(
      I18n.t("settings.profile.avatar_upload_hint", max: Users::AvatarUpload::MAX_MEGABYTES)
    ))
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.profile.avatar_crop.stage_label")))
    expect(response.body).to include(I18n.t("settings.profile.gravatar_label"))
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.profile.gravatar_hint")))
  end

  it "updates display name and biography" do
    sign_in_as

    patch settings_profile_path, params: { user: { display_name: "Marie des Alpes", bio: "Trail et vélo." } }

    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.display_name).to eq("Marie des Alpes")
    expect(user.bio).to eq("Trail et vélo.")
  end

  it "offers two independent audience selects defaulting to no sharing, with the whole-history notice" do
    sign_in_as

    get settings_profile_path

    page = response.parsed_body
    %w[profile_statistics_audience profile_records_audience].each do |attribute|
      select = page.at_css("select[name='user[#{attribute}]']")
      expect(select).to be_present
      expect(select.css("option").map { |option| option["value"] }).to eq(User::PROFILE_SHARING_AUDIENCES)
      expect(select.at_css("option[selected]")["value"]).to eq("none")
      expect(select.css("option").map(&:text)).to eq(User::PROFILE_SHARING_AUDIENCES.map { |audience| I18n.t("settings.profile.sharing.audiences.#{audience}") })
    end
    expect(page.at_css("#profile-sharing-privacy").text).to eq(I18n.t("settings.profile.sharing.privacy"))
    expect(page.at_css("#profile-sharing-privacy").parent.at_css("a[href='#{help_topic_path('publishing')}']").text).to eq(I18n.t("help.learn_more"))
    expect(page.at_css("select[name='user[profile_records_audience]']").ancestors("form").sole.css("input[name='user[display_name]']")).to be_empty
  end

  it "saves and revokes sharing choices independently without changing identity or publications" do
    sign_in_as
    name = user.display_name

    expect do
      patch settings_profile_path, params: { user: { profile_statistics_audience: "members", profile_records_audience: "none" } }
    end.not_to change(FederationOutboxEvent, :count)

    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.profile_statistics_audience).to eq("members")
    expect(user.profile_records_audience).to eq("none")
    expect(user.display_name).to eq(name)

    patch settings_profile_path, params: { user: { profile_records_audience: "followers" } }
    expect(user.reload.profile_statistics_audience).to eq("members")
    expect(user.profile_records_audience).to eq("followers")

    patch settings_profile_path, params: { user: { profile_statistics_audience: "none" } }
    expect(user.reload.profile_statistics_audience).to eq("none")
    expect(user.profile_records_audience).to eq("followers")

    patch settings_profile_path, params: { user: { profile_records_audience: "none" } }
    expect(user.reload.profile_records_audience).to eq("none")
  end

  it "rejects unknown audiences without partially saving the other choice" do
    sign_in_as

    patch settings_profile_path, params: { user: { profile_statistics_audience: "public", profile_records_audience: "followers" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload).to have_attributes(profile_statistics_audience: "none", profile_records_audience: "none")
    expect(response.parsed_body.text).to include(I18n.t("activerecord.attributes.user.profile_statistics_audience"))
  end

  it "offers discoverability off by default and saves the choice" do
    sign_in_as

    get settings_profile_path
    radios = response.parsed_body.css("input[name='user[discoverable]']")
    expect(radios.map { it["value"] }).to eq(User::DISCOVERABILITY)
    expect(radios.find { it["checked"] }["value"]).to eq("none")
    expect(response.parsed_body.text).to include(I18n.t("settings.profile.discoverability.hint"))

    patch settings_profile_path, params: { user: { discoverable: "members" } }

    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.discoverable).to eq("members")

    patch settings_profile_path, params: { user: { discoverable: "everyone" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.discoverable).to eq("members")
  end

  it "declares and clears the leaderboard category" do
    sign_in_as

    get settings_profile_path
    expect(response.parsed_body.css("input[name='user[leaderboard_category]']").map { it["value"] }).to eq(User::LEADERBOARD_CATEGORIES)
    expect(response.parsed_body.text).to include(I18n.t("settings.profile.leaderboard_category_privacy"))

    patch settings_profile_path, params: { user: { leaderboard_category: "women" } }
    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.leaderboard_category).to eq("women")

    patch settings_profile_path, params: { user: { leaderboard_category: "unspecified" } }
    expect(user.reload.leaderboard_category).to eq("unspecified")

    patch settings_profile_path, params: { user: { leaderboard_category: "other" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.leaderboard_category).to eq("unspecified")
  end

  it "rejects an overlong display name" do
    sign_in_as

    patch settings_profile_path, params: { user: { display_name: "x" * 61 } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.display_name).not_to eq("x" * 61)
  end

  it "opts in to Gravatar and enqueues a fetch" do
    sign_in_as

    expect do
      patch settings_profile_path, params: { user: { gravatar_opt_in: "1" } }
    end.to have_enqueued_job(Users::FetchGravatarCacheJob).with(user.id)

    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.gravatar_opt_in).to be(true)
  end

  it "uploads a normalized avatar and serves it through the application" do
    sign_in_as

    patch settings_profile_path, params: {
      user: { avatar: image_upload(width: 300, height: 120, format: ".jpg", content_type: "image/jpeg") }
    }

    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.avatar).to be_attached
    expect(user.avatar.content_type).to eq("image/webp")

    get profile_avatar_path(user.username)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/webp")
  end

  it "keeps the square the account chose" do
    sign_in_as

    patch settings_profile_path, params: {
      user: {
        avatar: image_upload(width: 128, height: 128),
        avatar_crop: { x: 64, y: 0, size: 64, width: 128, height: 128 }
      }
    }

    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.avatar).to be_attached
  end

  it "ignores a malformed crop and keeps the centred square" do
    sign_in_as

    patch settings_profile_path, params: {
      user: { avatar: image_upload(width: 128, height: 128), avatar_crop: { size: "0" } }
    }

    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.avatar).to be_attached
  end

  it "rejects an unsupported avatar with a translated error" do
    sign_in_as

    patch settings_profile_path, params: { user: { avatar: text_upload } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.profile.avatar_errors.unsupported_type")))
    expect(user.reload.avatar).not_to be_attached
  end

  it "removes the uploaded avatar without confirmation" do
    user.avatar.attach(io: StringIO.new("uploaded"), filename: "avatar.webp", content_type: "image/webp")
    sign_in_as

    patch settings_profile_path, params: { user: { remove_avatar: "1" } }

    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.avatar).not_to be_attached
  end

  it "shows the generate control only while the generated art is visible" do
    sign_in_as

    get settings_profile_path
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.profile.avatar_regenerate")))

    user.avatar.attach(io: StringIO.new("uploaded"), filename: "avatar.webp", content_type: "image/webp")
    get settings_profile_path
    expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("settings.profile.avatar_regenerate")))
  end

  it "rotates the generated avatar seed and renders the new preview" do
    sign_in_as
    previous = user.avatar_seed

    patch settings_profile_avatar_path

    expect(response).to have_http_status(:ok)
    expect(user.reload.avatar_seed).not_to eq(previous)
    expect(response.body).to include("<svg")
    expect(response.body).not_to include("<html")
  end

  it "requires authentication to regenerate the avatar" do
    patch settings_profile_avatar_path

    expect(response).to redirect_to(new_session_path)
  end

  it "ignores unpermitted attributes" do
    sign_in_as

    patch settings_profile_path, params: { user: { username: "hacked", theme: "dark" } }

    expect(user.reload.username).not_to eq("hacked")
    expect(user.theme).to eq("light")
  end
end
