# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Funding badge palette" do
  it "provides every allowed colour with at least 4.5:1 contrast against white" do
    source = Rails.root.join("app/frontend/styles/components/_funding.scss").read
    colours = source.scan(/&--(\w+) \{ background: #(\h{6}); \}/).to_h
    expect(colours.keys).to match_array(Allure::Funding::BADGE_COLORS)

    colours.each do |name, hex|
      channels = hex.scan(/../).map do |channel|
        srgb = channel.to_i(16) / 255.0
        srgb <= 0.04045 ? srgb / 12.92 : ((srgb + 0.055) / 1.055)**2.4
      end
      luminance = channels.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |channel, weight| channel * weight }
      expect(1.05 / (luminance + 0.05)).to be >= 4.5, "#{name} must keep white glyphs readable"
    end
  end
end
