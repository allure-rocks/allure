# frozen_string_literal: true

require "rails_helper"

# DESIGN.md §10.4: the shape says who you measure against — the trophy is a
# personal place, the laurel before a numeral a leaderboard place — and the
# tier colour says the place. Colour is never the only encoding (§18.6).
RSpec.describe MedalsHelper do
  describe "#rank_medal" do
    it "leads the top three with the laurel of their place before the plain numeral" do
      { 1 => [ "gold", "medals.first" ], 2 => [ "silver", "medals.second" ], 3 => [ "bronze", "medals.third" ] }
        .each do |rank, (tier, place_key)|
          fragment = Nokogiri::HTML.fragment(helper.rank_medal(rank))
          wreath = fragment.at_css("i.ti-laurel-wreath-#{rank}.allure-medal--#{tier}")
          numeral = fragment.at_css(".allure-rank-numeral")

          expect(wreath).to be_present
          expect(wreath["aria-hidden"]).to eq("true")
          expect(numeral.at_css("[aria-hidden=true]").text).to eq(rank.to_s)
          expect(numeral.at_css(".visually-hidden").text).to eq(I18n.t("medals.rank", rank:))
          expect(numeral["data-bs-title"]).to eq(I18n.t(place_key))
          expect(fragment.at_css(".ti-trophy")).to be_nil
        end
    end

    it "keeps the plain numeral from fourth place on, without a laurel, still spoken" do
      fragment = Nokogiri::HTML.fragment(helper.rank_medal(4))
      numeral = fragment.at_css(".allure-rank-numeral")

      expect(numeral.at_css("[aria-hidden=true]").text).to eq("4")
      expect(numeral.at_css(".visually-hidden").text).to eq(I18n.t("medals.rank", rank: 4))
      expect(numeral["data-controller"]).to be_nil
      expect(fragment.at_css("i")).to be_nil
    end

    it "appends the board size when given the participant count" do
      fragment = Nokogiri::HTML.fragment(helper.rank_medal(2, participants: 12))

      expect(fragment.at_css(".allure-medal--silver")).to be_present
      expect(fragment.text.squish).to end_with("/ 12")
      expect(Nokogiri::HTML.fragment(helper.rank_medal(5, participants: 9)).text.squish)
        .to eq("5#{I18n.t('medals.rank', rank: 5)} / 9")
    end
  end

  describe "#rank_stamp" do
    it "is the laurel on its tier's disc for the top three only" do
      expect(helper.rank_stamp(2)).to eq(icon: "ti-laurel-wreath-2", css: "allure-stamp--silver", label: I18n.t("medals.second"))
      expect(helper.rank_stamp(4)).to be_nil
    end
  end

  describe "#personal_place_icon" do
    it "renders the trophy in the place's colour with its spoken label and tooltip" do
      { 1 => [ "gold", "medals.record" ], 2 => [ "silver", "medals.personal_place.second" ],
        3 => [ "bronze", "medals.personal_place.third" ] }.each do |place, (tier, key)|
        tooltip = I18n.t(key, record: "10 km")
        fragment = Nokogiri::HTML.fragment(helper.personal_place_icon(place, "10 km"))

        expect(fragment.at_css("i.ti-trophy.allure-medal--#{tier}")["aria-hidden"]).to eq("true")
        expect(fragment.text).to eq(tooltip)
        expect(fragment.at_css("span")["data-bs-title"]).to eq(tooltip)
        expect(fragment.at_css(".ti-laurel-wreath-1, .ti-laurel-wreath-2, .ti-laurel-wreath-3")).to be_nil
      end
    end

    it "renders nothing outside the top three" do
      expect(helper.personal_place_icon(4, "10 km")).to be_nil
      expect(helper.personal_place_icon(nil, "10 km")).to be_nil
    end
  end

  describe "#personal_place_badge" do
    it "renders the neutral pill with the trophy and the short label" do
      tooltip = I18n.t("medals.records", records: I18n.t("records.types.fd"), count: 1)
      badge = Nokogiri::HTML.fragment(helper.personal_place_badge(1, tooltip:, text: "RP")).at_css("span.badge.bg-secondary-lt")

      expect(badge.at_css("i.ti-trophy.allure-medal--gold.me-1")).to be_present
      expect(badge.text).to eq("RP")
      expect(badge["aria-label"]).to eq(tooltip)
      expect(badge["data-bs-title"]).to eq(tooltip)
    end

    it "labels the second and third place by default" do
      badge = Nokogiri::HTML.fragment(helper.personal_place_badge(3, tooltip: "x")).at_css("span.badge")

      expect(badge.at_css("i.ti-trophy.allure-medal--bronze")).to be_present
      expect(badge.text).to eq(I18n.t("medals.personal_place_short.third"))
      expect(helper.personal_place_badge(4, tooltip: "x")).to be_nil
    end
  end

  describe "#personal_place_stamp" do
    it "is the trophy on its tier's disc" do
      expect(helper.personal_place_stamp(1, tooltip: "Record : FD"))
        .to eq(icon: "ti-trophy", css: "allure-stamp--gold", label: "Record : FD")
      expect(helper.personal_place_stamp(4, tooltip: "x")).to be_nil
    end
  end
end
