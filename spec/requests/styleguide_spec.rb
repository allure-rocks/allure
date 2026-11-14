# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Styleguide" do
  it "renders every component section with both themes and locales" do
    create(:sport, slug: "guide_sport", label: "Guide Sport", colour_group: "run")

    get styleguide_path

    expect(response).to have_http_status(:ok)
    %w[cards tiles buttons badges avatars tables filters alerts toasts modal states remote sports icons contrast].each do |section|
      expect(response.body).to include(%(id="sg-#{section}"))
    end
    expect(response.body.scan(/<h1[\s>]/).size).to eq(1)
    expect(response.body).to include('id="toasts"', 'id="confirm-modal"')
    expect(response.body).to include('viewBox="0 0 1000 1000"', "allure-record-badge", "allure-card-list")
    expect(response.body).to include('id="sg-filters-body"', "filter-toggle", "form-select-sm", "form-control-sm")
    expect(response.body).not_to include("ti-run")
  end

  it "renders the loading skeleton at a real content shape" do
    get styleguide_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("placeholder-glow", "allure-secondary-metrics")
    expect(response.body).to include(%(role="status">#{I18n.t("styleguide.states.loading")}))
  end

  it "shows the publication badge in every state, scheduled in both audience tints, in both fits" do
    get styleguide_path

    expect(response).to have_http_status(:ok)
    page = response.parsed_body.at_css("#sg-badges")
    expect(page.css("[data-audience-state].allure-badge-responsive").size).to eq(5)
    expect(page.css("[data-audience-state].allure-badge-icon").size).to eq(5)
    expect(page.text).to include(I18n.t("styleguide.badges.icon_only"))
    PublicationBadgeHelper::STATES.each_key do |state|
      expect(page.at_css(%([data-audience-state="#{state}"].allure-badge-responsive))).to be_present
      expect(page.at_css(%([data-audience-state="#{state}"].allure-badge-icon))).to be_present
    end
    expect(page.at_css('[data-audience-state="scheduled"][data-audience="followers"].bg-info-lt')).to be_present
    expect(page.at_css('[data-audience-state="scheduled"][data-audience="public"].bg-success-lt')).to be_present
  end

  it "renders the sport wall and the demo hooks" do
    get styleguide_path(locale: "en")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Component guide")
    expect(response.body).to include("data-controller=\"styleguide\"", "data-confirm-title")
  end

  it "stays out of the navigation tree" do
    get feed_path

    expect(response.body).not_to include(styleguide_path)
  end

  it "answers 404 in production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    get styleguide_path

    expect(response).to have_http_status(:not_found)
  end
end
