# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteSegmentAttachment do
  it "exposes the shared media seam" do
    attachment = build(:remote_segment_attachment, remote_segment: create(:remote_segment))

    expect(attachment.owner).to eq(attachment.remote_segment)
    expect(attachment.source_domain).to eq(attachment.remote_segment.source_domain)
    expect(attachment.fetch_job_class).to eq(Federation::FetchRemoteSegmentAttachmentJob)
    expect(attachment.filename_stem).to eq("remote-segment-#{attachment.remote_segment_id}")
  end

  it "validates kind, status, and purged state" do
    expect(build(:remote_segment_attachment, kind: "video")).not_to be_valid
    expect(build(:remote_segment_attachment, status: "unknown")).not_to be_valid
    expect(build(:remote_segment_attachment, status: "purged", blob_id: 1)).not_to be_valid
  end

  it "is unique per course and kind" do
    attachment = create(:remote_segment_attachment)

    expect(build(:remote_segment_attachment, remote_segment: attachment.remote_segment, kind: attachment.kind))
      .not_to be_valid
  end
end
