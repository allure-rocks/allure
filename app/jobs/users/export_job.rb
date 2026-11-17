# frozen_string_literal: true

module Users
  # Builds one requested data export (docs/dev/ACCOUNT.md): the archive is
  # written to a temporary file, attached, and the account is told in-app and
  # by mail. A failure marks the row failed and tells nobody; the account may
  # ask again after the cooldown.
  class ExportJob < ApplicationJob
    queue_as :default

    def perform(export_id)
      export = AccountExport.find_by(id: export_id)
      return unless export && export.status == "pending"

      export.update!(status: "running", started_at: Time.current)
      Tempfile.create([ "allure-export-", ".zip" ], binmode: true) do |file|
        counts = ExportArchive.new(user: export.user).write(file.path)
        export.archive.attach(io: File.open(file.path, "rb"), filename: export.filename, content_type: "application/zip")
        now = Time.current
        export.update!(status: "ready", counts:, byte_size: File.size(file.path), completed_at: now,
                       expires_at: now + AccountExport::LIFETIME)
      end
      Notifications::Create.new(user: export.user, kind: "account_export_ready", subject: export).call!
      AccountMailer.export_ready(export).deliver_later
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, export_id: })
      export&.update_columns(status: "failed", error_code: "build_failed", completed_at: Time.current, updated_at: Time.current)
    end
  end
end
