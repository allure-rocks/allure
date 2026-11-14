# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Diagnostics do
  it "aggregates status counts, blocks, and peer policies" do
    create(:federation_inbox_item, status: "processed")
    create(:federation_inbox_item, status: "failed")
    domain_block = create(:federation_domain_block, domain: "blocked.example")
    actor_block = create(:federation_actor_block, actor_uri: "https://blocked.example/users/demo")
    policy = create(:federation_peer_policy, domain: "peer.example", capability_profile: "restricted_fetch")
    note = create(:remote_note, status: "active")
    segment = create(:remote_segment, status: "active")
    create(:federation_delivery, status: "delivered", inbox_url: "https://remote.example/inbox")
    create(:remote_note_attachment, remote_note: note, status: "failed")
    create(:remote_segment_attachment, remote_segment: segment, status: "failed")

    result = described_class.new.call

    expect(result.inbox_items).to eq("processed" => 1, "failed" => 1)
    expect(result.remote_notes).to eq("active" => 1)
    expect(result.remote_segments).to eq("active" => 1)
    expect(result.media).to include("failed" => 2)
    expect(result.retryable_media).to eq(2)
    expect(result.deliveries).to include([ [ "delivered", "remote.example" ], 1 ])
    expect(result.domain_blocks).to contain_exactly(domain_block)
    expect(result.actor_blocks).to contain_exactly(actor_block)
    expect(result.peer_policies).to contain_exactly(policy)
  end

  it "never exposes coordinates, raw payloads, remote HTML, or keys" do
    raw_marker = "RAW-PAYLOAD-MARKER"
    html_marker = "<script>HTML-MARKER</script>"
    coordinate_marker = 6.123456
    actor = create(:actor, uri: "https://remote.example/users/demo", summary: html_marker)
    create(
      :remote_note,
      actor:,
      raw: { "marker" => raw_marker },
      representation: {
        "title" => "Marker",
        "location" => { "longitude" => coordinate_marker, "latitude" => 45.0 }
      }
    )
    create(:federation_inbox_item, raw: { "marker" => raw_marker })

    serialized = described_class.new.call.inspect

    expect(serialized).not_to include(raw_marker)
    expect(serialized).not_to include(html_marker)
    expect(serialized).not_to include(coordinate_marker.to_s)
  end
end
