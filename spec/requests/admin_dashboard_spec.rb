# frozen_string_literal: true

require "rails_helper"

# The administration shell and dashboard (docs/dev/ADMIN.md): operator-only,
# 404 for everyone else, and never linked from a member's HTML.
RSpec.describe "Admin dashboard" do
  let(:operator) { create(:user, :with_totp, username: "operator") }
  let(:member) { create(:user) }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    example.run
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  it "redirects an anonymous visitor to sign in" do
    get admin_root_path

    expect(response).to redirect_to(new_session_path)
  end

  it "answers 404 to a signed-in non-operator" do
    sign_in_as(member)

    get admin_root_path

    expect(response).to have_http_status(:not_found)
  end

  it "renders the console for the operator" do
    sign_in_as(operator)
    create(:workout, user: member, sport: catalog_sport("running"))

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.pretitle"))
    expect(response.body).to include(I18n.t("admin.dashboard.title"))
    expect(response.body).to include(I18n.t("navigation.admin_dashboard"))
    expect(response.body).to include(I18n.t("admin.exit"))
    expect(response.body).to include(
      I18n.t("admin.dashboard.accounts.activity",
             connected: Session.distinct.count(:user_id),
             active: Users::Engagement.new.active(since: 7.days.ago))
    )
    expect(response.body.scan("<h1").size).to eq(1)
    wordmark = Nokogiri::HTML(response.body).at_css("header .allure-wordmark")
    expect(wordmark.text).to eq("allure.")
    expect(wordmark.ancestors("a").first["aria-label"]).to eq(I18n.t("admin.console"))
  end

  it "links the console from the account menu only for the operator" do
    sign_in_as(operator)
    get me_path

    expect(response.body).to include(%(href="#{admin_root_path}"))
  end

  it "never emits an admin link for a member" do
    sign_in_as(member)
    get me_path

    # Scope to the href: release-note copy may legitimately mention /admin,
    # but no member's HTML may carry a console link.
    expect(response.body).not_to match(%r{href="/admin(?:/|")})
    expect(response.body).not_to include(I18n.t("navigation.administration"))
  end
end
