# frozen_string_literal: true

require "rails_helper"
require "json"

RSpec.describe "Allure wire fixtures" do
  def fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/federation/#{name}").read)
  end

  it "pins the strict public Create profile" do
    activity = fixture("allure_note.json")
    note = activity.fetch("object")

    expect(activity.fetch("type")).to eq("Create")
    expect(note.fetch("type")).to eq("Note")
    expect(note.fetch("attributedTo")).to eq(activity.fetch("actor"))
    expect(URI(note.fetch("id")).host).to eq(URI(activity.fetch("actor")).host)
    expect(activity.fetch("to")).to include("https://www.w3.org/ns/activitystreams#Public")
    expect(note.fetch("tag").map { |tag| tag.fetch("name") }).to include("category", "elevation_gain", "commute")
    expect(note.fetch("attachment").map { |attachment| attachment.fetch("mediaType") })
      .to contain_exactly("image/png", "application/xml+gpx")
  end

  it "pins the strict course Create profile" do
    activity = fixture("allure_segment_note.json")
    note = activity.fetch("object")

    expect(activity.fetch("type")).to eq("Create")
    expect(note.fetch("type")).to eq("Note")
    expect(URI(note.fetch("id")).path).to start_with("/api/v1/segment/")
    expect(note.fetch("attributedTo")).to eq(activity.fetch("actor"))
    expect(note.fetch("tag").map { |tag| tag.fetch("name") })
      .to include("segment_kind", "sport_slug", "match_tolerance", "average_grade")
    expect(note.fetch("attachment").map { |attachment| attachment.fetch("mediaType") })
      .to contain_exactly("image/png", "application/xml+gpx")
    expect(note.fetch("attachment").map { |attachment| attachment.fetch("name") })
      .to contain_exactly("Route image", "GPX course")

    parsed = Federation::Parsers::RemoteSegment.new(activity).call

    expect(parsed.name).to eq("Col du Test")
    expect(parsed.sport_slug).to eq("cycling")
    expect(parsed.attachments.map(&:kind)).to contain_exactly("gpx", "route_image")
  end

  it "pins the publication Delete shape" do
    activity = fixture("allure_delete.json")

    expect(activity.fetch("type")).to eq("Delete")
    expect(activity.fetch("object")).to be_a(String)
    expect(URI(activity.fetch("object"))).to be_absolute
  end

  it "pins the Reject shape" do
    activity = fixture("allure_reject.json")

    expect(activity.fetch("type")).to eq("Reject")
    expect(activity.fetch("object")).to include("/activities/")
  end

  it "pins the actor Delete tombstone shape" do
    activity = fixture("allure_actor_delete.json")

    expect(activity.fetch("type")).to eq("Delete")
    expect(activity.dig("object", "type")).to eq("Tombstone")
    expect(activity.dig("object", "formerType")).to eq("Person")
  end
end
