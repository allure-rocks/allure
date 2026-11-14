# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeedsHelper do
  include ActiveSupport::Testing::TimeHelpers

  let(:paris) { Time.find_zone("Europe/Paris") }
  let(:viewer) { build(:user, time_zone: "Europe/Paris") }

  before do
    v = viewer
    helper.define_singleton_method(:current_user) { v }
  end

  def item(published_at)
    Federation::FollowingFeed::Item.new(kind: "local", record: nil, published_at:)
  end

  describe "#feed_day_label" do
    it "names today, yesterday and the day before, then the weekday date" do
      travel_to(paris.local(2026, 9, 16, 12)) do
        expect(helper.feed_day_label(Date.new(2026, 9, 16))).to eq("Aujourd'hui")
        expect(helper.feed_day_label(Date.new(2026, 9, 15))).to eq("Hier")
        expect(helper.feed_day_label(Date.new(2026, 9, 14))).to eq("Avant-hier")
        expect(helper.feed_day_label(Date.new(2026, 9, 11))).to eq("vendredi 11 septembre")
        expect(helper.feed_day_label(Date.new(2025, 12, 24))).to eq("mercredi 24 décembre 2025")
      end
    end

    it "anchors today on the viewer's zone" do
      viewer.time_zone = "Pacific/Auckland"
      travel_to(Time.utc(2026, 9, 15, 23, 30)) do
        expect(helper.feed_day_label(Date.new(2026, 9, 16))).to eq("Aujourd'hui")
      end
    end
  end

  describe "#feed_days" do
    it "chunks adjacent items by publication day in the viewer's zone" do
      a = item(paris.local(2026, 9, 16, 9))
      b = item(Time.utc(2026, 9, 15, 23, 30)) # 01:30 in Paris on the 16th
      c = item(paris.local(2026, 9, 15, 8))
      d = item(paris.local(2026, 9, 16, 7)) # out of order on purpose: never merged back

      groups = helper.feed_days([ a, b, c, d ])

      expect(groups.map(&:first)).to eq([ Date.new(2026, 9, 16), Date.new(2026, 9, 15), Date.new(2026, 9, 16) ])
      expect(groups.map { |_, items| items.length }).to eq([ 2, 1, 1 ])
    end

    it "returns nothing for an empty page" do
      expect(helper.feed_days([])).to eq([])
    end
  end

  describe "#feed_excerpt" do
    it "collapses whitespace, bounds the text and stays nil when empty" do
      expect(helper.feed_excerpt("  Une   sortie\n\nmatinale ")).to eq("Une sortie matinale")
      expect(helper.feed_excerpt("mot " * 200).length).to be <= FeedsHelper::FEED_EXCERPT_LENGTH
      expect(helper.feed_excerpt("mot " * 200)).to end_with("…")
      expect(helper.feed_excerpt("   ")).to be_nil
      expect(helper.feed_excerpt(nil)).to be_nil
    end
  end

  describe "#feed_author_for" do
    it "reduces a local account to its username handle" do
      user = build(:user, username: "marie", display_name: "Marie Dufour")
      workout = build(:workout, user:)
      author = helper.feed_author_for(Federation::FollowingFeed::Item.new(kind: "local", record: workout, published_at: Time.current))

      expect(author.name).to eq("Marie Dufour")
      expect(author.handle).to eq("@marie")
      expect(author.path).to eq("/@marie")
      expect(author.remote).to be(false)
    end

    it "keeps a remote actor's instance in the handle" do
      actor = build(:actor, uri: "https://remote.example/users/demo", handle: "demo@remote.example",
                            acct: "demo@remote.example", display_name: "Demo Remote")
      note = build(:remote_note, actor:)
      author = helper.feed_author_for(Federation::FollowingFeed::Item.new(kind: "remote", record: note, published_at: Time.current))

      expect(author.name).to eq("Demo Remote")
      expect(author.handle).to eq("@demo@remote.example")
      expect(author.remote).to be(true)
    end
  end
end
