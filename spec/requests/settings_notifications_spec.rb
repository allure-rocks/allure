# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings notifications" do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "renders both preference switches" do
    get settings_notifications_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      ERB::Util.html_escape(I18n.t("settings.notifications.follow_requests_label")),
      ERB::Util.html_escape(I18n.t("settings.notifications.follow_accepted_label"))
    )
  end

  it "updates each preference independently" do
    patch settings_notifications_path, params: { user: { notify_follow_requests: "0" } }

    expect(response).to redirect_to(settings_notifications_path)
    expect(user.reload.notify_follow_requests).to be(false)
    expect(user.notify_follow_accepted).to be(true)

    patch settings_notifications_path, params: { user: { notify_follow_accepted: "0" } }

    expect(user.reload.notify_follow_accepted).to be(false)
  end

  it "switches the automatic-publication notices independently" do
    get settings_notifications_path
    expect(response.body).to include(
      ERB::Util.html_escape(I18n.t("settings.notifications.auto_published_label")),
      ERB::Util.html_escape(I18n.t("settings.notifications.auto_publication_failed_label"))
    )

    patch settings_notifications_path, params: { user: { notify_auto_published: "0" } }

    expect(user.reload.notify_auto_published).to be(false)
    expect(user.notify_auto_publication_failed).to be(true)
  end

  it "links the page from the settings shell" do
    get settings_profile_path

    expect(response.body).to include(settings_notifications_path)

    get settings_notifications_path

    expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.hub.notifications.title")))
  end
end
