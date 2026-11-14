# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::StravaArchive::MediaCaptions do
  it "maps each photo to its caption, whatever the header language" do
    captions = described_class.parse(
      "Nom de fichier du support,Légende du support\nmedia/a.jpg,Sur l'eau\nmedia/b.jpg,\n../c.jpg,Ailleurs\n"
    )

    expect(captions).to eq("media/a.jpg" => "Sur l'eau")
  end

  it "reads nothing from a missing or broken file" do
    expect(described_class.parse(nil)).to eq({})
    expect(described_class.parse("a,\"b\n")).to eq({})
  end
end
