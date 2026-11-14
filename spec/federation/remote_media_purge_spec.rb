# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RemoteMedia::Purge do
  let(:note) { create(:remote_note, audience:) }
  let(:audience) { "public" }
  let!(:attachment) do
    create(:remote_note_attachment, remote_note: note, status: "cached", blob:)
  end
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("data"),
      filename: "media-#{SecureRandom.hex(4)}.gpx",
      content_type: "application/xml+gpx"
    )
  end

  context "with a followers-only note" do
    let(:audience) { "followers" }

    it "purges blobs and redacts location when no entitlement remains" do
      create(:remote_note_recipient, remote_note: note).withdraw!(reason: "unfollow")

      described_class.new(owner: note).call!

      expect(attachment.reload).to be_purged
      expect(attachment.blob_id).to be_nil
      expect { blob.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(note.reload).to be_location_data_purged
      expect(note.representation.fetch("redacted")).to be(true)
    end
  end

  # PLAN_M5 §9.6: any signed-in account may still open a public copy, so one
  # account's unfollow must not blank another's media.
  it "retains a public note's media when the last entitlement is withdrawn" do
    create(:remote_note_recipient, remote_note: note).withdraw!(reason: "unfollow")

    described_class.new(owner: note).call!

    expect(attachment.reload).to be_cached
    expect(attachment.blob_id).to eq(blob.id)
    expect(note.reload).not_to be_location_data_purged
  end

  it "forces the purge for an author's withdrawal" do
    create(:remote_note_recipient, remote_note: note).withdraw!(reason: "deleted")

    described_class.new(owner: note).call!(force: true)

    expect(attachment.reload).to be_purged
    expect(note.reload).to be_location_data_purged
  end

  it "keeps the media while another recipient remains entitled" do
    create(:remote_note_recipient, remote_note: note)

    described_class.new(owner: note).call!

    expect(attachment.reload).to be_cached
    expect(attachment.blob_id).to eq(blob.id)
    expect(note.reload).not_to be_location_data_purged
  end

  it "is idempotent" do
    note.mark_deleted!

    described_class.new(owner: note).call!
    expect { described_class.new(owner: note).call! }.not_to change(RemoteNoteAttachment, :count)
    expect(attachment.reload).to be_purged
  end
end
