# frozen_string_literal: true

# docs/dev/API.md: `api_idempotency_keys.response_body` is encrypted at rest
# from here on. The rows kept so far are in clear and would not decrypt, so
# they go; the replay store lives 24 hours and a retry whose first response
# is gone simply runs the request again.
class PurgeApiIdempotencyKeysBeforeEncryption < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM api_idempotency_keys"
  end

  def down
    # Nothing to restore: the purged rows were a replay cache.
  end
end
