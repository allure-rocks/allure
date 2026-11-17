# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The problem codes of the REST API (docs/dev/API.md). Titles and details
      # are protocol text, English only (§13.3); `code` is what clients branch
      # on, and docs/openapi/v1.yaml lists the same set.
      module Problems
        CATALOG = {
          "missing_token" => [ "Authentication required", "Send an API token in the Authorization header: Bearer <token>." ],
          "invalid_token" => [ "Invalid token", "The API token is unknown, revoked or expired." ],
          "account_suspended" => [ "Account suspended", "The account this token belongs to is suspended." ],
          "account_deletion_scheduled" => [ "Account deletion scheduled",
                                            "The account this token belongs to is scheduled for deletion." ],
          "second_factor_required" => [ "Two-step verification required",
                                        "Set up two-step verification on the website before using the API." ],
          "insufficient_scope" => [ "Insufficient scope", "The token does not grant this operation." ],
          "not_found" => [ "Not found", "The resource does not exist or is not visible to this token." ],
          "invalid_parameter" => [ "Invalid parameter", "A request parameter is invalid." ],
          "invalid_cursor" => [ "Invalid cursor", "The cursor is malformed or belongs to another ordering." ],
          "validation_failed" => [ "Validation failed", "Some fields were refused; see errors." ],
          "sport_change_failed" => [ "Sport change failed",
                                     "The workout could not be analysed again for the new sport; nothing was changed." ],
          "credited_workout" => [ "Credited workout",
                                  "This workout is another account's activity credited to you: it can only be deleted." ],
          "acknowledgement_required" => [ "Acknowledgement required",
                                          "Show your user what will be shared, then send acknowledge: true." ],
          "publication_refused" => [ "Publication refused", "The workout cannot be published with this profile; see reason." ],
          "not_scheduled" => [ "Not scheduled", "Only a scheduled publication can be activated or rescheduled." ],
          "webhook_inactive" => [ "Webhook inactive", "The webhook is paused or disabled; enable it first." ],
          "import_finished" => [ "Import finished", "The import has already finished and can no longer be cancelled." ],
          "import_limit" => [ "Import limit reached",
                              "Too many imports are waiting, or the day's upload budget is spent; see reason." ],
          "idempotency_key_reused" => [ "Idempotency key reused",
                                        "This Idempotency-Key was already used with a different request." ],
          "idempotency_key_in_progress" => [ "Request in progress",
                                             "A request with this Idempotency-Key is still running; retry later." ],
          "rate_limited" => [ "Too many requests", "Wait for the Retry-After delay before sending more requests." ]
        }.freeze

        CODES = CATALOG.keys.freeze

        module_function

        def title(code) = CATALOG.fetch(code).first
        def detail(code) = CATALOG.fetch(code).last
      end
    end
  end
end
