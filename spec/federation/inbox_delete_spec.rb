# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Inbox::Delete do
  let(:recipient) { create(:local_actor) }
  let(:author) { create(:actor, uri: "https://remote.example/users/demo") }
  let(:activity) { federation_delete_activity }
  let(:item) do
    create(
      :federation_inbox_item,
      recipient_actor: recipient,
      activity_uri: activity.fetch("id"),
      activity_type: "Delete",
      actor_uri: author.uri,
      raw: activity
    )
  end

  def process(activity: self.activity, item: self.item)
    described_class.new(item:, activity:).call!
  end

  it "tombstones the note, withdraws entitlements, and redacts location data" do
    note = create(:remote_note, actor: author, object_uri: activity.fetch("object"))
    create(:remote_note_recipient, remote_note: note, recipient_actor: recipient)
    create(:remote_note_attachment, remote_note: note)

    result = process

    expect(result.reload).to be_deleted
    expect(result).to be_location_data_purged
    expect(result.representation.fetch("redacted")).to be(true)
    expect(result.representation).not_to have_key("location")
    expect(result.recipients).to all(be_withdrawn)
    expect(result.attachments).to all(be_purged)
    expect(result.entitled_to?(recipient)).to be(false)
  end

  it "creates a durable tombstone for a Delete before Create" do
    result = process

    expect(result).to be_deleted
    expect(result.object_uri).to eq(activity.fetch("object"))
    expect(result).to be_location_data_purged
    expect(RemoteNote.active.count).to eq(0)
  end

  it "rejects a Delete from a different actor" do
    note = create(:remote_note, actor: author, object_uri: activity.fetch("object"))

    expect { process(activity: federation_delete_activity(overrides: { "actor" => "https://other.example/users/x" })) }
      .to raise_error(Federation::Inbox::Rejected, /does not match the sender/)
    expect(note.reload).to be_active
  end

  it "rejects a Delete for another author's object" do
    other_author = create(:actor, uri: "https://remote.example/users/other")
    note = create(:remote_note, actor: other_author, object_uri: activity.fetch("object"))

    expect { process }.to raise_error(Federation::Inbox::Rejected, /author does not match/)
    expect(note.reload).to be_active
  end

  it "rejects a Delete that would tombstone another instance's note" do
    foreign = "https://victim.example/api/v1/trail/victim-note"
    attempt = federation_delete_activity(object: foreign)

    expect { process(activity: attempt) }
      .to raise_error(Federation::Inbox::Rejected, /authority does not match/)
    expect(RemoteNote.where(object_uri: foreign)).to be_empty
  end

  it "rejects a Delete that would tombstone another instance's course" do
    foreign = "https://victim.example/api/v1/segment/victim-course"
    attempt = federation_delete_activity(
      object: { "id" => foreign, "type" => "Tombstone" }
    )

    expect { process(activity: attempt) }
      .to raise_error(Federation::Inbox::Rejected, /authority does not match/)
    expect(RemoteSegment.where(object_uri: foreign)).to be_empty
  end

  it "is idempotent for a repeated Delete" do
    note = create(:remote_note, actor: author, object_uri: activity.fetch("object"))
    first = process
    second = process

    expect(second).to eq(first)
    expect(note.reload).to be_deleted
  end

  it "accepts an embedded object" do
    embedded = {
      "id" => activity.fetch("object"),
      "type" => "Tombstone"
    }

    expect { process(activity: federation_delete_activity(object: embedded)) }
      .to change(RemoteNote, :count).by(1)
  end

  it "rejects an invalid object id" do
    expect { process(activity: federation_delete_activity(object: "not-a-uri")) }
      .to raise_error(Federation::Inbox::Rejected, /object id is invalid/)
  end

  describe "an actor Delete" do
    let(:actor_delete) do
      {
        "id" => "https://remote.example/activities/delete-actor-1",
        "type" => "Delete",
        "actor" => author.uri,
        "object" => {
          "id" => author.uri,
          "type" => "Tombstone",
          "formerType" => "Person",
          "deleted" => Time.current.iso8601
        },
        "to" => [ recipient.uri ],
        "cc" => []
      }
    end

    it "tombstones the author and withdraws and purges its notes" do
      note = create(:remote_note, actor: author)
      attachment = create(:remote_note_attachment, remote_note: note, status: "cached")
      create(:remote_note_recipient, remote_note: note, recipient_actor: recipient)

      result = process(
        activity: actor_delete,
        item: create(
          :federation_inbox_item,
          recipient_actor: recipient,
          activity_uri: actor_delete.fetch("id"),
          activity_type: "Delete",
          actor_uri: author.uri,
          raw: actor_delete
        )
      )

      expect(result).to eq(author)
      expect(author.reload).to be_tombstoned
      expect(note.reload).to be_location_data_purged
      expect(note.recipients).to all(be_withdrawn)
      expect(attachment.reload).to be_purged
    end

    it "ends every relationship with the deleted author, in both directions" do
      following = create(:following, :accepted, follower_actor: recipient, followed_actor: author)
      follower = create(:following, :accepted, follower_actor: author, followed_actor: recipient,
                                               uri: "https://remote.example/activities/follow-back")

      process(
        activity: actor_delete,
        item: create(:federation_inbox_item, recipient_actor: recipient, activity_uri: actor_delete.fetch("id"),
                                             activity_type: "Delete", actor_uri: author.uri, raw: actor_delete)
      )

      expect([ following.reload, follower.reload ]).to all(be_undone)
      expect(FederationOutboxEvent.where(activity_type: "Undo")).to be_empty
    end

    it "rejects an actor Delete for an uncached author" do
      unknown = actor_delete.merge("actor" => "https://remote.example/users/unknown")
      unknown["object"] = unknown["object"].merge("id" => unknown["actor"])

      expect {
        process(
          activity: unknown,
          item: create(
            :federation_inbox_item,
            recipient_actor: recipient,
            activity_uri: unknown.fetch("id"),
            activity_type: "Delete",
            actor_uri: unknown.fetch("actor"),
            raw: unknown
          )
        )
      }.to raise_error(Federation::Inbox::Rejected, /not cached/)
    end

    it "withdraws notifications caused by the author" do
      notification = create(:notification, user: recipient.user, actor: author)

      process(
        activity: actor_delete,
        item: create(
          :federation_inbox_item,
          recipient_actor: recipient,
          activity_uri: actor_delete.fetch("id"),
          activity_type: "Delete",
          actor_uri: author.uri,
          raw: actor_delete
        )
      )

      expect(Notification.where(id: notification.id)).not_to exist
    end
  end
end
