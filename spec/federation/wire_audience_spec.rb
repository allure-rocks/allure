# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Outbox::WireAudience do
  let(:followers) { "https://allure.example/users/marie/followers" }
  let(:listed) do
    %w[
      https://one.example/users/a
      https://one.example/users/b
      https://two.example/users/c
      https://three.example:8443/users/d
    ]
  end
  let(:audience) { { "recipients" => listed, "to" => [ followers ], "cc" => [] } }
  let(:payload) do
    { "type" => "Delete", "actor" => "https://allure.example/users/marie", "object" => { "type" => "Tombstone" },
      "recipients" => listed, "to" => [ followers ], "cc" => [] }
  end

  it "keeps only the destination's own actors from the listed recipients" do
    projected = described_class.project(payload:, audience:, authorities: [ "one.example" ])

    expect(projected["recipients"]).to eq(%w[https://one.example/users/a https://one.example/users/b])
    expect(projected["to"]).to eq([ followers ])
    expect(projected.except("recipients")).to eq(payload.except("recipients"))
  end

  it "keys authorities with their port" do
    projected = described_class.project(payload:, audience:, authorities: [ "three.example:8443" ])

    expect(projected["recipients"]).to eq(%w[https://three.example:8443/users/d])
  end

  it "filters every addressing key, as a withdrawn publication's Delete lists its recipients in to" do
    delete = { "type" => "Delete", "object" => "https://allure.example/api/v1/trail/x", "to" => listed, "cc" => [] }

    projected = described_class.project(payload: delete, audience: { "recipients" => listed, "to" => listed },
                                        authorities: [ "two.example" ])

    expect(projected["to"]).to eq(%w[https://two.example/users/c])
  end

  it "leaves an event without listed recipients unchanged" do
    create = { "type" => "Create", "to" => [ "https://www.w3.org/ns/activitystreams#Public" ], "cc" => [ followers ] }

    expect(described_class.project(payload: create, audience: { "to" => create["to"] }, authorities: [])).to eq(create)
  end

  it "shows a reader without an actor none of the listed recipients" do
    expect(described_class.project(payload:, audience:, authorities: [ nil ])["recipients"]).to eq([])
  end
end
