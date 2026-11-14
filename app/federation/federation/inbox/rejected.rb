# frozen_string_literal: true

module Federation
  module Inbox
    # A terminally invalid inbound activity. The item is rejected and never
    # retried; transient failures keep raising ordinary errors and retry.
    class Rejected < StandardError; end
  end
end
