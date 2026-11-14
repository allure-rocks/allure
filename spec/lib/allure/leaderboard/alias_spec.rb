# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Leaderboard::Alias do
  let(:secret_key_base) { "slice-one-test-secret" }

  it "matches the fixed vector for the configured secret" do
    expect(described_class.for(user_id: 7, segment_id: 11, secret_key_base:)).to eq("Climber 87")
  end

  it "returns a stable deterministic alias" do
    first = described_class.for(user_id: 7, segment_id: 11, secret_key_base:)
    second = described_class.for(user_id: 7, segment_id: 11, secret_key_base:)

    expect(first).to eq(second)
    expect(first).to match(/\A\w+ \d+\z/)
  end

  it "changes the alias when the segment changes" do
    first = described_class.for(user_id: 7, segment_id: 11, secret_key_base:)
    second = described_class.for(user_id: 7, segment_id: 12, secret_key_base:)

    expect(first).not_to eq(second)
  end

  it "localizes the word list" do
    french = described_class.for(user_id: 7, segment_id: 11, locale: :fr, secret_key_base:)
    english = described_class.for(user_id: 7, segment_id: 11, locale: :en, secret_key_base:)
    german = described_class.for(user_id: 7, segment_id: 11, locale: :de, secret_key_base:)

    expect(french).not_to eq(english)
    expect(german).to eq("Kletterer 87")
    expect(french.split.last).to eq(english.split.last)
  end

  it "has a word in every account locale" do
    expect(described_class::WORDS).to all(satisfy { |word| User::LOCALES.all? { word[it.to_sym].present? } })
  end

  it "falls back to English for a locale without words" do
    expect(described_class.for(user_id: 7, segment_id: 11, locale: :pt, secret_key_base:)).to eq("Climber 87")
  end

  it "resolves collisions deterministically by appending a digit" do
    base = described_class.for(user_id: 7, segment_id: 11, secret_key_base:)

    expect(
      described_class.resolve(
        user_id: 7,
        segment_id: 11,
        existing: [ base, "#{base} 2" ],
        secret_key_base:
      )
    ).to eq("#{base} 3")
  end
end
