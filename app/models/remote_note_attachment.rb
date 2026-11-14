# frozen_string_literal: true

require "uri"

# The persisted attachment descriptor for a received note. The row exists
# before any remote fetch: receipt records what the Note declared, and the
# fetch/verify/purge pipeline runs afterwards (PLAN_M5 §7.4).
class RemoteNoteAttachment < ApplicationRecord
  include RemoteMediaAttachment

  TERMINAL_STATUSES = %w[cached failed unavailable purged].freeze

  belongs_to :remote_note, inverse_of: :attachments
  belongs_to :blob, class_name: "ActiveStorage::Blob", optional: true

  validates :kind, uniqueness: { scope: [ :remote_note_id, :theme ] }

  # The shared media seam: the fetch, recovery, and retry services dispatch
  # through these.
  def fetch_job_class = Federation::FetchRemoteNoteAttachmentJob
  def filename_stem = "remote-note-#{remote_note_id}"
end
