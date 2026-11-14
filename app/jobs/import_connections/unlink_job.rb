# frozen_string_literal: true

module ImportConnections
  # Disconnects a service (PLAN_REMOTE_IMPORTS.md §6.2): revokes what the
  # provider allows, deletes the imported workouts and equipment when the
  # owner chose to, and wipes every credential. The row stays `unlinked`, so
  # kept workouts keep their external id and a later link never imports them
  # again. Idempotent: a rerun finishes what an interrupted one started.
  class UnlinkJob < ApplicationJob
    queue_as :remote_imports

    limits_concurrency key: ->(connection, **) { connection.id.to_s }, group: ImportConnection::CONCURRENCY_GROUP,
                       duration: 2.hours

    def perform(connection, delete_data: true)
      return unless connection.unlinking?

      deauthorize(connection)
      delete_imported(connection) if delete_data
      connection.update!(status: "unlinked", credentials: {}, token_expires_at: nil, pending_expires_at: nil,
                         external_account_name: nil, last_sync_error: nil)
      Notifications::Withdraw.new(user: connection.user, subject: connection).call!
    end

    private

    def deauthorize(connection)
      return if connection.credentials.to_h.except("return_status").empty?

      Providers.for(connection).deauthorize!
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, connection_id: connection.id })
    end

    # Each workout goes through the ordinary deletion, so its publications are
    # withdrawn and their Delete activities expanded as for any deletion.
    def delete_imported(connection)
      connection.workouts.find_each do |workout|
        Workouts::WorkoutDeletion.new(user: connection.user, workout:).call!
      end
      connection.equipments.find_each(&:destroy!)
    end
  end
end
