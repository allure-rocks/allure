# frozen_string_literal: true

require "rails_helper"

# DESIGN.md §10.4: one publication badge for every surface that states a
# workout's or a course's sharing state — one mark, one tint per state, and the
# label printed from `md` up and only visually hidden below it.
RSpec.describe PublicationBadgeHelper do
  def badge(html)
    Nokogiri::HTML.fragment(html).at_css("span")
  end

  it "names every state with the publication mark and its own tint" do
    {
      "public" => [ "bg-success-lt", "ti-broadcast", I18n.t("workouts.publication.audience.public") ],
      "followers" => [ "bg-info-lt", "ti-broadcast", I18n.t("workouts.publication.audience.followers") ],
      "scheduled" => [ "bg-success-lt", "ti-broadcast", I18n.t("workouts.scheduled.badge") ],
      "unpublished" => [ "bg-secondary-lt", "ti-broadcast-off", I18n.t("workouts.publication.unpublished") ]
    }.each do |state, (css, icon, label)|
      node = badge(helper.publication_badge(state))

      expect(node["class"]).to include("badge", css)
      expect(node.at_css(".ti")["class"]).to eq("ti #{icon} me-1")
      expect(node.at_css(".allure-badge-responsive__label").text).to eq(label)
      expect(node["data-audience-state"]).to eq(state)
    end
  end

  it "prints the label from md up and only hides it visually below, where the tooltip names the state" do
    node = badge(helper.publication_badge("public"))

    expect(node["class"]).to include("allure-badge-responsive")
    expect(node["class"]).not_to include("allure-badge-icon")
    # The label is in the DOM at every width: the state is never carried by
    # colour alone (§18.6).
    expect(node.at_css(".visually-hidden")).to be_nil
    expect(node["data-controller"]).to eq("tooltip")
    expect(node["data-bs-title"]).to eq(I18n.t("workouts.publication.audience.public"))
    expect(node["data-tooltip-media-value"]).to eq(BadgesHelper::ICON_ONLY_MEDIA)
    # The focus stop belongs to the tooltip, and the tooltip only exists below
    # `md`; the controller adds it there.
    expect(node["tabindex"]).to be_nil
  end

  it "keeps the icon-only form, with its own tooltip and focus stop, where there is no room" do
    node = badge(helper.publication_badge("followers", fit: :icon))

    expect(node["class"]).to include("allure-badge-icon")
    expect(node["class"]).not_to include("allure-badge-responsive")
    expect(node.at_css(".visually-hidden").text).to eq(I18n.t("workouts.publication.audience.followers"))
    expect(node["data-tooltip-media-value"]).to be_nil
    expect(node["tabindex"]).to eq("0")
  end

  it "pulses the mark of the one state its owner can still cancel" do
    expect(badge(helper.publication_badge("scheduled"))["class"]).to include("allure-badge-pulse")
    expect(badge(helper.publication_badge("scheduled", fit: :icon))["class"]).to include("allure-badge-pulse")
    expect(badge(helper.publication_badge("public"))["class"]).not_to include("allure-badge-pulse")
  end

  it "tints a scheduled publication with the audience it will reach, never amber" do
    followers = badge(helper.publication_badge("scheduled", audience: "followers"))
    expect(followers["class"]).to include("bg-info-lt", "allure-badge-pulse")
    expect(followers["data-audience"]).to eq("followers")

    public_badge = badge(helper.publication_badge("scheduled", audience: "public", fit: :icon))
    expect(public_badge["class"]).to include("bg-success-lt", "allure-badge-pulse")
    expect(public_badge["class"]).not_to include("bg-warning-lt")
  end

  it "lets a surface name the state in its own words" do
    node = badge(helper.publication_badge("public", label: "Publié : Public"))

    expect(node.text).to include("Publié : Public")
    expect(node["data-bs-title"]).to eq("Publié : Public")
  end

  it "renders a course's visibility as the same badge with the course's wording" do
    node = badge(helper.segment_visibility_badge("followers_only"))

    expect(node["class"]).to include("bg-info-lt")
    expect(node.at_css(".ti")["class"]).to include("ti-broadcast")
    expect(node.text).to include(I18n.t("segments.visibility.followers_only"))
    expect(node["data-audience-state"]).to eq("followers")
    expect(node["data-segment-visibility"]).to eq("followers_only")

    private_node = badge(helper.segment_visibility_badge("private"))
    expect(private_node["class"]).to include("bg-secondary-lt")
    expect(private_node.at_css(".ti")["class"]).to include("ti-broadcast-off")
  end

  it "refuses an unknown state instead of rendering an unmarked badge" do
    expect { helper.publication_badge("draft") }.to raise_error(ArgumentError, /draft/)
  end
end
