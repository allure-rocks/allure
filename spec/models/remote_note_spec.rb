# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteNote do
  subject(:note) { build(:remote_note) }

  it "is valid from the factory" do
    expect(note).to be_valid
  end

  it "requires a unique object URI and absolute URIs" do
    existing = create(:remote_note)
    duplicate = build(:remote_note, object_uri: existing.object_uri)

    expect(duplicate).not_to be_valid

    note.object_uri = "not-a-uri"
    note.activity_uri = "also-not-a-uri"
    expect(note).not_to be_valid
    expect(note.errors[:object_uri]).to be_present
    expect(note.errors[:activity_uri]).to be_present
  end

  it "requires the source domain to match the author" do
    note.source_domain = "other.example"
    expect(note).not_to be_valid
  end

  it "keeps the deleted state and timestamp in agreement" do
    note.status = "deleted"
    expect(note).not_to be_valid

    note.deleted_at = Time.current
    expect(note).to be_valid
  end

  it "validates the representation snapshot" do
    note.representation = { "metrics" => { "not_a_metric" => 1.0 } }
    expect(note).not_to be_valid

    note.representation = { "redacted" => true, "location" => { "longitude" => 1.0, "latitude" => 2.0 } }
    expect(note).not_to be_valid
  end

  it "validates the record markers" do
    note.representation = { "record_types" => %w[BOGUS] }
    expect(note).not_to be_valid

    note.representation = { "record_types" => %w[FD], "record_distances" => %w[km5] }
    expect(note).to be_valid
  end

  it "validates the commute flag as a boolean" do
    note.representation = { "commute" => true }
    expect(note).to be_valid

    note.representation = { "commute" => false }
    expect(note).to be_valid

    note.representation = { "commute" => "true" }
    expect(note).not_to be_valid
  end

  it "validates the closed-comments flag as presence-only" do
    note.representation = { "comments_closed" => true }
    expect(note).to be_valid

    note.representation = { "comments_closed" => false }
    expect(note).not_to be_valid
  end

  it "marks deleted notes without touching the tombstone again" do
    note.save!

    note.mark_deleted!

    expect(note).to be_deleted
    expect(note.deleted_at).to be_present
  end

  it "redacts location-bearing representation once" do
    note = create(
      :remote_note,
      representation: {
        "title" => "Hike", "metrics" => {}, "sport_label" => "Hiking",
        "location" => { "longitude" => 6.4, "latitude" => 45.0 }
      }
    )

    note.redact_location!
    first = note.location_data_purged_at

    expect(note.representation).to eq(
      "title" => "Hike", "sport_label" => "Hiking", "metrics" => {}, "redacted" => true
    )
    expect(note.route_metadata).to eq("redacted" => true)

    note.redact_location!
    expect(note.location_data_purged_at).to eq(first)
  end

  it "scopes active notes by entitlement" do
    note = create(:remote_note)
    actor = create(:local_actor)
    create(:remote_note_recipient, remote_note: note, recipient_actor: actor)

    expect(described_class.entitled_to(actor)).to include(note)
    expect(described_class.entitled_to(create(:local_actor))).not_to include(note)
  end
end
