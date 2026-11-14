# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RemoteMedia::Retry do
  it "resets and re-enqueues failed and unavailable descriptors" do
    failed = create(:remote_note_attachment, status: "failed", attempts: 3)
    unavailable = create(:remote_note_attachment, status: "unavailable", attempts: 5)
    cached = create(:remote_note_attachment, status: "cached")

    expect { described_class.new.call }
      .to have_enqueued_job(Federation::FetchRemoteNoteAttachmentJob).exactly(2).times

    expect(failed.reload).to be_pending
    expect(failed.attempts).to eq(0)
    expect(unavailable.reload).to be_pending
    expect(unavailable.attempts).to eq(0)
    expect(cached.reload).to be_cached
  end

  it "skips descriptors whose note is no longer active" do
    deleted = create(:remote_note, :deleted)
    create(:remote_note_attachment, remote_note: deleted, status: "failed")

    expect { described_class.new.call }
      .not_to have_enqueued_job(Federation::FetchRemoteNoteAttachmentJob)
  end
end
