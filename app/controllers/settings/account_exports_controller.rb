# frozen_string_literal: true

module Settings
  # The data export (PLAN_ACCOUNT.md §3): a request needs a recent proof of
  # identity and is built in the background; the archive is streamed from the
  # application, owner-scoped, never through a raw storage URL. An account in
  # its deletion window may still download its last export.
  class AccountExportsController < ApplicationController
    allow_deletion_window_access only: :download
    before_action :require_recent_authentication, only: :create

    def create
      export = nil
      AccountExport.transaction do
        current_user.lock!
        export = current_user.account_exports.create!(status: "pending") if AccountExport.requestable_for?(current_user)
      end
      return redirect_to settings_account_path, alert: t("settings.account.export.flash.unavailable") unless export

      Users::ExportJob.perform_later(export.id)
      redirect_to settings_account_path, notice: t("settings.account.export.flash.requested")
    rescue ActiveRecord::RecordNotUnique
      redirect_to settings_account_path, alert: t("settings.account.export.flash.unavailable")
    end

    def download
      export = current_user.account_exports.find_by_short_id!(params[:id])
      raise ActiveRecord::RecordNotFound unless export.downloadable?

      blob = export.archive.blob
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Content-Type"] = "application/zip"
      response.headers["Content-Length"] = blob.byte_size.to_s
      response.headers["Content-Disposition"] =
        ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: export.filename)
      # A validator is present, so Rack::ETag never buffers the body to hash
      # it: the archive streams chunk by chunk from storage.
      response.headers["Last-Modified"] = export.completed_at.httpdate
      self.response_body = Enumerator.new { |chunks| blob.download { chunks << it } }
    end
  end
end
