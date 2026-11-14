# frozen_string_literal: true

# Acknowledges the release notes the footer dialog just showed.
#
# The seen state is the per-account version marker
# (User#release_notes_seen_version) rather than browser storage, so each
# release is announced once per account, across every device. JSON only: the
# dialog PATCHes from the browser, exactly like the theme toggle.
class ReleaseNotesController < ApplicationController
  def update
    current_user.update!(release_notes_seen_version: Allure::VERSION)
    head :no_content
  end
end
