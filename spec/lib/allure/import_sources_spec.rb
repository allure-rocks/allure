# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::ImportSources do
  it "registers unique sources with a known kind" do
    keys = described_class.all.map(&:key)

    expect(keys).to eq(keys.uniq)
    expect(described_class.all.map(&:kind)).to all(be_in(described_class::KINDS))
  end

  it "finds a source by string or symbol key" do
    expect(described_class.for("file")).to eq(described_class::FILE)
    expect(described_class.for(:igpsport_device)).to eq(described_class::IGPSPORT_DEVICE)
    expect(described_class.for("unknown")).to be_nil
  end

  it "offers a remote source only while the operator enables it" do
    with_remote_import_enabled(enabled: false) do
      expect(described_class.enabled).to eq([
        described_class::FILE, described_class::STRAVA_ARCHIVE, described_class::IGPSPORT_DEVICE, described_class::MANUAL
      ])
    end
    with_remote_import_enabled do
      expect(described_class.enabled).to include(described_class::GARMIN_CONNECT)
    end
    expect(described_class.remote).to all(be_remote)
    expect(described_class.remote.map(&:key)).to match_array(Allure::RemoteImports::Config.providers)
  end

  it "always offers the manual source, which owns its own form" do
    expect(described_class.for(:manual)).to be_manual
    expect(described_class.enabled).to include(described_class::MANUAL)
  end

  it "always offers the Strava archive, which submits from its own panel" do
    expect(described_class.for(:strava_archive)).to be_archive
    expect(described_class.enabled).to include(described_class::STRAVA_ARCHIVE)
  end

  it "ships a translated label and a partial for every source" do
    described_class.all.each do |source|
      %i[fr en].each do |locale|
        key = "workouts.batch_import.sources.#{source.key}.label"
        expect(I18n.exists?(key, locale)).to be(true), "missing #{key} in #{locale}"
      end

      partial = Rails.root.join("app/views/workout_imports/sources/_#{source.key}.html.erb")
      expect(partial).to exist
    end
  end
end
