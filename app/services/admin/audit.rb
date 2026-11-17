# frozen_string_literal: true

module Admin
  # The single write seam for the operator audit log (docs/dev/ADMIN.md). Every
  # admin mutation records through here, so a new control cannot silently skip
  # the log.
  module Audit
    module_function

    def record(actor:, action:, subject: nil, metadata: {})
      AdminEvent.create!(
        user: actor,
        action: action.to_s,
        subject: subject,
        metadata: metadata.presence || {}
      )
    end
  end
end
