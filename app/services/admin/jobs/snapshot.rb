# frozen_string_literal: true

module Admin
  module Jobs
    # A bounded, read-only view of the Solid Queue database for the live jobs
    # panel: per-queue depths and latency, process heartbeats, the latest failed
    # executions, the next scheduled jobs, and recurring tasks.
    #
    # Counts are grouped queries, and the lists are capped, so the panel can
    # poll every few seconds without scanning job tables.
    class Snapshot
      RECENT_FAILURES = 20
      SCHEDULED_PREVIEW = 10

      QueueRow = Data.define(:name, :ready, :scheduled, :claimed, :blocked, :failed, :latency, :paused)

      RecurringRow = Data.define(:key, :schedule, :queue_name, :last_enqueued_time, :next_time)

      Result = Data.define(
        :queues, :processes, :recurring_tasks, :failed_executions, :failed_count,
        :scheduled_executions, :alive_threshold
      )

      def call
        Result.new(
          queues: queues,
          processes: SolidQueue::Process.order(:kind, :name).to_a,
          recurring_tasks: recurring_tasks,
          failed_executions: SolidQueue::FailedExecution.includes(:job).order(created_at: :desc, id: :desc)
            .limit(RECENT_FAILURES),
          failed_count: SolidQueue::FailedExecution.count,
          scheduled_executions: SolidQueue::ScheduledExecution.includes(:job).order(:scheduled_at, :id)
            .limit(SCHEDULED_PREVIEW),
          alive_threshold: SolidQueue.process_alive_threshold
        )
      end

      private

      # Command tasks carry no queue of their own: Solid Queue enqueues them
      # through `SolidQueue::RecurringJob`, whose queue is the gem's internal
      # one. Resolving it here keeps the panel from showing a queue the jobs
      # never land on.
      def recurring_tasks
        SolidQueue::RecurringTask.order(:key).map do |task|
          RecurringRow.new(
            key: task.key,
            schedule: task.schedule,
            queue_name: task.queue_name.presence || SolidQueue::RecurringJob.queue_name,
            last_enqueued_time: task.last_enqueued_time,
            next_time: task.next_time
          )
        end
      end

      def queues
        ready = SolidQueue::ReadyExecution.group(:queue_name).count
        scheduled = SolidQueue::ScheduledExecution.group(:queue_name).count
        claimed = SolidQueue::ClaimedExecution.joins(:job).group("solid_queue_jobs.queue_name").count
        blocked = SolidQueue::BlockedExecution.group(:queue_name).count
        failed = SolidQueue::FailedExecution.joins(:job).group("solid_queue_jobs.queue_name").count
        oldest = SolidQueue::ReadyExecution.group(:queue_name).minimum(:created_at)
        paused = SolidQueue::Pause.pluck(:queue_name)

        names = (ready.keys | scheduled.keys | claimed.keys | blocked.keys | failed.keys | paused).sort
        now = Time.current

        names.map do |name|
          QueueRow.new(
            name:,
            ready: ready[name].to_i,
            scheduled: scheduled[name].to_i,
            claimed: claimed[name].to_i,
            blocked: blocked[name].to_i,
            failed: failed[name].to_i,
            latency: oldest[name] ? (now - oldest[name]).to_i : 0,
            paused: paused.include?(name)
          )
        end
      end
    end
  end
end
