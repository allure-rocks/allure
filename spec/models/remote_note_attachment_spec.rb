# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteNoteAttachment do
  subject(:attachment) { build(:remote_note_attachment) }

  it "is valid from the factory" do
    expect(attachment).to be_valid
  end

  it "validates the kind, status, and URL" do
    attachment.kind = "video"
    attachment.status = "unknown"
    attachment.remote_url = "not-a-uri"

    expect(attachment).not_to be_valid
    expect(attachment.errors[:kind]).to be_present
    expect(attachment.errors[:status]).to be_present
    expect(attachment.errors[:remote_url]).to be_present
  end

  it "uniquely describes one kind per note" do
    existing = create(:remote_note_attachment)
    duplicate = build(:remote_note_attachment, remote_note: existing.remote_note, kind: existing.kind)

    expect(duplicate).not_to be_valid
  end

  it "refuses a blob on a purged descriptor" do
    attachment.status = "purged"
    attachment.blob_id = 1
    attachment.content_digest = "abc"
    attachment.byte_size = 10

    expect(attachment).not_to be_valid
  end
end
