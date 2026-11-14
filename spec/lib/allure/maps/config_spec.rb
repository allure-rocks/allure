# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Maps::Config do
  describe "defaults" do
    it "serves the OpenFreeMap light and dark styles" do
      config = described_class.new

      expect(config.style_url).to eq("https://tiles.openfreemap.org/styles/liberty")
      expect(config.dark_style_url).to eq("https://tiles.openfreemap.org/styles/dark")
      expect(config).to be_theme_aware
      expect(config).to be_secure
    end

    it "reads both styles from the environment" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MAP_STYLE_URL").and_return("https://tiles.example/styles/day")
      allow(ENV).to receive(:[]).with("MAP_STYLE_URL_DARK").and_return("https://tiles.example/styles/night")

      config = described_class.new

      expect(config.style_url).to eq("https://tiles.example/styles/day")
      expect(config.dark_style_url).to eq("https://tiles.example/styles/night")
    end
  end

  describe "raster template" do
    it "defaults to the OSM raster tiles showing the same geography" do
      config = described_class.new

      expect(config.raster_template).to eq("https://tile.openstreetmap.org/{z}/{x}/{y}.png")
      expect(config).to be_raster_secure
    end

    it "reads the template from the environment" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MAP_RASTER_TEMPLATE").and_return("https://tiles.internal/{z}/{x}/{y}.png?key=abc")

      expect(described_class.new.raster_template).to eq("https://tiles.internal/{z}/{x}/{y}.png?key=abc")
    end

    it "rejects a template without placeholders" do
      expect { described_class.new(raster_template: "https://tiles.internal/tiles.png") }
        .to raise_error(described_class::InvalidRasterTemplate, /{z}, {x} and {y}/)
    end

    it "rejects credentials, which tile URLs would leak to the tile host logs" do
      expect { described_class.new(raster_template: "https://user:secret@tiles.internal/{z}/{x}/{y}.png") }
        .to raise_error(described_class::InvalidRasterTemplate, /credentials/)
    end

    it "rejects a non-HTTP scheme" do
      expect { described_class.new(raster_template: "ftp://tiles.internal/{z}/{x}/{y}.png") }
        .to raise_error(described_class::InvalidRasterTemplate, /http or https/)
    end

    it "is not raster-secure over plain HTTP" do
      expect(described_class.new(raster_template: "http://tiles.internal/{z}/{x}/{y}.png")).not_to be_raster_secure
    end
  end

  describe "dark style fallback" do
    it "reuses a custom light style rather than mixing in the default provider" do
      config = described_class.new(style_url: "https://tiles.internal/styles/basemap")

      expect(config.dark_style_url).to eq("https://tiles.internal/styles/basemap")
      expect(config).not_to be_theme_aware
    end

    it "keeps the dark default when nothing is configured at all" do
      config = described_class.new

      expect(config.dark_style_url).to eq(described_class::DEFAULT_DARK_STYLE_URL)
    end

    it "treats a blank dark style as absent" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MAP_STYLE_URL").and_return("https://tiles.internal/styles/basemap")
      allow(ENV).to receive(:[]).with("MAP_STYLE_URL_DARK").and_return("")

      expect(described_class.new.dark_style_url).to eq("https://tiles.internal/styles/basemap")
    end
  end

  describe "#style_url_for" do
    subject(:config) do
      described_class.new(
        style_url: "https://tiles.example/styles/day",
        dark_style_url: "https://tiles.example/styles/night"
      )
    end

    it "selects by theme" do
      expect(config.style_url_for(theme: "dark")).to eq("https://tiles.example/styles/night")
      expect(config.style_url_for(theme: "light")).to eq("https://tiles.example/styles/day")
    end

    it "falls back to the light style for an unknown or missing theme" do
      expect(config.style_url_for(theme: nil)).to eq("https://tiles.example/styles/day")
      expect(config.style_url_for(theme: "sepia")).to eq("https://tiles.example/styles/day")
    end
  end

  describe "validation" do
    it "rejects a relative URL" do
      expect { described_class.new(style_url: "/styles/liberty") }
        .to raise_error(described_class::InvalidStyleUrl, /must be absolute/)
    end

    it "rejects a non-HTTP scheme" do
      expect { described_class.new(style_url: "ftp://tiles.example/styles/day") }
        .to raise_error(described_class::InvalidStyleUrl, /must be http or https/)
    end

    it "rejects credentials, which a data attribute would publish to the browser" do
      expect { described_class.new(style_url: "https://user:secret@tiles.example/styles/day") }
        .to raise_error(described_class::InvalidStyleUrl, /must not contain credentials/)
    end

    it "names the offending variable when the dark style is the invalid one" do
      expect { described_class.new(style_url: "https://tiles.example/day", dark_style_url: "nonsense") }
        .to raise_error(described_class::InvalidStyleUrl, /MAP_STYLE_URL_DARK/)
    end

    it "keeps a query string, which self-hosted tile servers use for keys" do
      config = described_class.new(style_url: "https://tiles.internal/styles/day?key=abc")

      expect(config.style_url).to eq("https://tiles.internal/styles/day?key=abc")
    end

    it "is not secure when configured over plain HTTP" do
      expect(described_class.new(style_url: "http://tiles.internal/styles/day")).not_to be_secure
    end
  end
end
