# frozen_string_literal: true

# Counts the SQL statements a block issues, for N+1 guards: a list rendered
# with two items and with twelve must cost the same number of queries.
# Schema reads and query-cache hits are not statements.
module QueryCounting
  def count_queries
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      count += 1
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end

RSpec.configure do |config|
  config.include QueryCounting
end
