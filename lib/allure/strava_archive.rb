# frozen_string_literal: true

module Allure
  # The archive Strava sends when an athlete requests their data
  # (docs/dev/STRAVA-ARCHIVE.md). The file source caps an upload at 500 MB; an
  # archive is one file holding a whole history, so it gets its own cap.
  module StravaArchive
    MAX_BYTES = 2 * 1024 * 1024 * 1024
    MAX_SIZE_LABEL = "2 GB"
  end
end
