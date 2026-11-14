# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::ReleaseNotes do
  around do |example|
    described_class.reset!
    example.run
    described_class.reset!
  end

  # The shipped data file is the contract under test: the footer dialog exists
  # because the running release has curated notes. A release that removes them
  # moves this example with it.
  it "ships curated notes for the running release in every supported locale" do
    data = YAML.safe_load_file(described_class::PATH, aliases: false)
    User::LOCALES.each do |locale|
      expect(data.dig(locale.to_s, Allure::VERSION)).not_to be_empty
    end
  end

  it "falls back to English when the requested locale has no entry" do
    expect(described_class.for(version: Allure::VERSION, locale: :it)).to eq(
      described_class.for(version: Allure::VERSION, locale: :en)
    )
  end

  it "returns nothing for a version without notes" do
    expect(described_class.for(version: "99.99.99", locale: :fr)).to eq([])
  end

  it "fails closed when the data file is missing" do
    stub_const("Allure::ReleaseNotes::PATH", Rails.root.join("config/release_notes_absent.yml"))

    expect(described_class.for(version: Allure::VERSION, locale: :fr)).to eq([])
  end

  it "fails closed when the data file is malformed" do
    path = Rails.root.join("tmp/release_notes_malformed.yml")
    File.write(path, "fr: [unclosed")
    stub_const("Allure::ReleaseNotes::PATH", path)

    expect(described_class.for(version: Allure::VERSION, locale: :fr)).to eq([])
  ensure
    File.delete(path) if File.exist?(path)
  end
end
