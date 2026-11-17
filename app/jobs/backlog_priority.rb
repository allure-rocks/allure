# frozen_string_literal: true

# History runs behind new outings (docs/dev/STRAVA-ARCHIVE.md). A bulk
# import — a Strava archive, a file batch over five entries, a date-range
# retrieval — queues thousands of enrichments (route images, places, segment
# matching, weather, photos). Enqueued at the default
# priority they would run oldest first, and a member's ride uploaded meanwhile
# would wait hours for its map.
#
# Every job enqueued inside `BacklogPriority.enqueue { … }` that names no
# priority of its own gets `PRIORITY`. Solid Queue runs ready jobs and releases
# jobs held back by a concurrency limit by ascending priority (0 first), so the
# backlog only runs when nothing newer waits. A job running at the backlog
# priority enqueues its own follow-ups at it too (`ApplicationJob`), so a
# terrain profile's re-analysis or a photo's placement stays behind as well.
module BacklogPriority
  PRIORITY = 10
  KEY = :allure_backlog_priority

  module_function

  def enqueue(active: true)
    return yield unless active

    previous = ActiveSupport::IsolatedExecutionState[KEY]
    ActiveSupport::IsolatedExecutionState[KEY] = true
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[KEY] = previous if active
  end

  def active? = ActiveSupport::IsolatedExecutionState[KEY] == true

  def backlog?(job) = job.priority.to_i >= PRIORITY
end
