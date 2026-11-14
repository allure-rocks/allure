# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RemoteMedia::Recovery do
  let(:now) { Time.utc(2026, 9, 11, 12) }
  let(:note) { create(:remote_note) }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "enqueues pending and due failed descriptors" do
    create(:remote_note_attachment, remote_note: note)
    create(:remote_note_attachment, remote_note: note, kind: "route_image", status: "failed",
           next_attempt_at: now - 1.minute)

    expect { described_class.new(now:).call }
      .to change { enqueued_jobs_for(Federation::FetchRemoteNoteAttachmentJob) }.by(2)
  end

  it "does not enqueue a future retry or an exhausted descriptor" do
    create(:remote_note_attachment, remote_note: note, status: "failed", next_attempt_at: now + 1.hour)
    create(:remote_note_attachment, remote_note: note, kind: "route_image", status: "failed",
           attempts: Federation::RemoteMedia::Fetch::MAX_ATTEMPTS, next_attempt_at: now - 1.minute)

    expect { described_class.new(now:).call }
      .not_to change { enqueued_jobs_for(Federation::FetchRemoteNoteAttachmentJob) }
  end

  it "releases a stale fetching descriptor and leaves a fresh one alone" do
    stale = create(:remote_note_attachment, remote_note: note, status: "fetching")
    stale.update_column(:updated_at, now - described_class::STALE_FETCHING_AFTER - 1.minute)
    fresh = create(:remote_note_attachment, remote_note: note, kind: "route_image", status: "fetching")
    fresh.update_column(:updated_at, now)

    described_class.new(now:).call

    expect(stale.reload.status).to eq("failed")
    expect(stale.next_attempt_at).to eq(now)
    expect(fresh.reload.status).to eq("fetching")
  end

  def enqueued_jobs_for(job_class)
    ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == job_class }
  end
end
