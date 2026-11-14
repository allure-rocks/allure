# frozen_string_literal: true

require "uri"

# The persisted attachment descriptor for a received course. The row exists
# before any remote fetch: receipt only records what the Note declared, and the
# fetch/verify/purge pipeline runs afterwards
# (PLAN_SEGMENTS_FEDERATION.md §7.4).
class RemoteSegmentAttachment < ApplicationRecord
  include RemoteMediaAttachment

  TERMINAL_STATUSES = %w[cached failed unavailable purged].freeze

  belongs_to :remote_segment, inverse_of: :attachments
  belongs_to :blob, class_name: "ActiveStorage::Blob", optional: true

  validates :kind, uniqueness: { scope: [ :remote_segment_id, :theme ] }

  # The shared media seam: the fetch, recovery, and retry services dispatch
  # through these.
  def fetch_job_class = Federation::FetchRemoteSegmentAttachmentJob
  def filename_stem = "remote-segment-#{remote_segment_id}"
end
