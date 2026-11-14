# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Parsers::Activity do
  let(:base_activity) do
    {
      "id" => "https://remote.example/activities/1",
      "type" => "Follow",
      "actor" => "https://remote.example/users/demo",
      "object" => "http://allure.test:3000/users/marie"
    }
  end

  it "normalizes a valid activity without mutating it" do
    result = described_class.new(base_activity).call

    expect(result.id).to eq(base_activity.fetch("id"))
    expect(result.type).to eq("Follow")
    expect(result.actor).to eq(base_activity.fetch("actor"))
    expect(result.document).to eq(base_activity)
  end

  it "accepts deferred activity types without interpreting their objects" do
    activity = base_activity.merge("type" => "Create", "object" => { "type" => "Note" })

    expect { described_class.new(activity).call }.not_to raise_error
  end

  it "rejects malformed identity fields" do
    [
      base_activity.except("id"),
      base_activity.merge("id" => "not a URI"),
      base_activity.merge("actor" => "https://user:password@remote.example/users/demo"),
      base_activity.merge("object" => { "id" => "https://allure.test/object" })
    ].each do |activity|
      expect { described_class.new(activity).call }.to raise_error(described_class::InvalidActivity)
    end
  end

  # Allure's own activity URIs are deterministic, so an id on a foreign
  # authority is the handle a third party would use to squat the URI of a
  # peer's future Delete or Follow (PLAN_M2.md §6.4).
  it "rejects an activity id that lives on another authority than the actor" do
    [
      base_activity.merge("id" => "https://peer.example/api/v1/trail/abc/activities/1"),
      base_activity.merge("id" => "https://remote.example:8443/activities/1"),
      base_activity.merge("id" => "http://remote.example/activities/1", "actor" => "https://remote.example:8443/users/demo")
    ].each do |activity|
      expect { described_class.new(activity).call }
        .to raise_error(described_class::InvalidActivity, "activity id authority does not match the actor")
    end
  end

  it "compares the id and actor authorities with the host folded and the default port elided" do
    [
      base_activity.merge("id" => "https://REMOTE.example/activities/1"),
      base_activity.merge("id" => "https://remote.example:443/activities/1")
    ].each do |activity|
      expect(described_class.new(activity).call.id).to eq(activity.fetch("id"))
    end
  end

  it "requires the object shape for Undo" do
    activity = base_activity.merge("type" => "Undo", "object" => { "type" => "Follow" })

    expect { described_class.new(activity).call }.to raise_error(described_class::InvalidActivity)
  end
end
