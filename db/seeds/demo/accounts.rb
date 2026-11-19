# frozen_string_literal: true

module DemoSeed
  # Which row a manifest account names (docs/dev/DEMO.md). The username is the
  # account's immutable identity, so it wins over the address: a re-seed on a
  # database seeded under another domain renames the account instead of
  # colliding with it. On a database that has never seen the account, the
  # address is the second key.
  module Accounts
    module_function

    def find_or_initialize(username:, email:)
      User.find_by(username:) || User.find_or_initialize_by(email_address: email)
    end
  end
end
