# frozen_string_literal: true

require "rails_helper"

# DESIGN.md §10.4: the viewer's own item and an activity done with someone are
# state badges like the publication state — their icon, the primary tint, the
# label printed from `md` up and only visually hidden below it.
RSpec.describe BadgesHelper do
  def badge(html)
    Nokogiri::HTML.fragment(html).children.first
  end

  it "marks the viewer's own item with the user circle in the primary tint" do
    node = badge(helper.mine_badge(label: "À moi"))

    expect(node.name).to eq("span")
    expect(node["class"]).to include("badge", "bg-primary-lt", "allure-badge-responsive")
    expect(node.at_css(".ti")["class"]).to eq("ti ti-user-circle me-1")
    expect(node.at_css(".allure-badge-responsive__label").text).to eq("À moi")
    expect(node["data-badge"]).to eq("mine")
    expect(node["data-tooltip-media-value"]).to eq(BadgesHelper::ICON_ONLY_MEDIA)
    expect(node["tabindex"]).to be_nil
  end

  it "keeps the icon-only form with its tooltip and focus stop" do
    node = badge(helper.mine_badge(label: "Vous", fit: :icon))

    expect(node["class"]).to include("allure-badge-icon")
    expect(node.at_css(".visually-hidden").text).to eq("Vous")
    expect(node["data-bs-title"]).to eq("Vous")
    expect(node["tabindex"]).to eq("0")
  end

  it "names an activity done with someone, and opens its source as a link" do
    node = badge(helper.together_badge("Avec Marie", href: "/workouts/abc"))

    expect(node.name).to eq("a")
    expect(node["href"]).to eq("/workouts/abc")
    expect(node["class"]).to include("bg-primary-lt")
    expect(node.at_css(".ti")["class"]).to include("ti-users")
    expect(node["data-badge"]).to eq("together")
    # A link is focusable on its own: no extra focus stop.
    expect(node["tabindex"]).to be_nil
  end

  it "names everyone in a tooltip shown at every width when the label is shortened" do
    node = badge(helper.together_badge("Avec Eva et 2 autres", tooltip: "Avec Eva, Joan et Inès"))

    expect(node.name).to eq("span")
    expect(node.at_css(".allure-badge-responsive__label").text).to eq("Avec Eva et 2 autres")
    expect(node["data-bs-title"]).to eq("Avec Eva, Joan et Inès")
    expect(node["data-tooltip-media-value"]).to be_nil
    expect(node["tabindex"]).to eq("0")

    icon = badge(helper.together_badge("Avec Eva et 2 autres", tooltip: "Avec Eva, Joan et Inès", fit: :icon))
    expect(icon.at_css(".visually-hidden").text).to eq("Avec Eva, Joan et Inès")
  end

  it "turns grey once the source is deleted" do
    node = badge(helper.together_badge("Avec Marie · activité source supprimée", detached: true, fit: :icon))

    expect(node.name).to eq("span")
    expect(node["class"]).to include("bg-secondary-lt", "allure-badge-icon")
    expect(node["class"]).not_to include("bg-primary-lt")
  end
end
