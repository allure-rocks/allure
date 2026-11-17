# frozen_string_literal: true

module Users
  # Account deletion is a federation lifecycle, not a bare row delete: the
  # actor's publications are withdrawn and a signed actor Delete is durable
  # before the user row disappears. The tombstoned actor remains to answer
  # 410 and to deliver the withdrawal until its key is retired.
  #
  # The deletion runs in phases (docs/dev/ACCOUNT.md), each idempotent and
  # skipped once done, so a purge interrupted half-way resumes where it
  # stopped: the cut-off, provider subscription cancellation, the federation
  # withdrawal, the workouts one by one, then the row with its remaining small
  # rows. `call!` answers true once the
  # row is gone, false when `limit` workouts were deleted and work remains,
  # and raises `Cancelled` when `require_scheduled:` was asked and the window
  # was cancelled before the cut-off ran.
  class DeleteAccount
    # A cancellation that committed after the purge job's guard but before the
    # cut-off: nothing runs, and the account keeps everything.
    class Cancelled < StandardError; end

    def initialize(user:, now: Time.current, require_scheduled: false)
      @user = user
      @now = now
      @require_scheduled = require_scheduled
    end

    def call!(limit: nil)
      cut_off!
      # Billing identifiers stay until the provider confirms that no future
      # renewal can charge this account. A transient failure resumes here.
      Funding::CancelSubscriptions.call(user: @user)
      withdraw_from_federation!
      return false unless delete_workouts!(limit)

      @user.destroy!
      true
    end

    private

    # From here on the deletion can no longer be cancelled, nothing runs on
    # the account's behalf and nobody can sign in to it. The purge job demands
    # the scheduled window it was enqueued for (`require_scheduled:`): the
    # cancellation just won the row lock between the job's guard and this
    # one, and it must win for good (docs/dev/ACCOUNT.md).
    def cut_off!
      return if @user.deletion_started?

      User.transaction do
        @user.lock!
        raise Cancelled, "the deletion was cancelled" if @require_scheduled && !@user.deletion_scheduled?

        @user.update_columns(
          deletion_requested_at: @user.deletion_requested_at || @now,
          deletion_scheduled_at: @user.deletion_scheduled_at || @now,
          deletion_requested_by: @user.deletion_requested_by || "operator",
          deletion_started_at: @now
        )
        # Push subscriptions go with their session (FK cascade).
        @user.sessions.delete_all
        @user.api_tokens.delete_all
        @user.recovery_codes.delete_all
        @user.webauthn_credentials.delete_all
        @user.identities.delete_all
      end
      Admin::Audit.record(actor: nil, action: :account_deleted,
                          metadata: { "username" => @user.username, "by" => @user.deletion_requested_by })
      # Credentials of connected services leave first: nothing may sign in to
      # them on the account's behalf while the purge runs.
      @user.import_connections.find_each(&:destroy!)
      @user.workout_import_batches.where(status: %w[queued processing]).find_each(&:cancel!)
      @user.workout_bulk_operations.where.not(status: WorkoutBulkOperation::TERMINAL_STATUSES).find_each(&:cancel!)
    end

    def withdraw_from_federation!
      actor = @user.actor
      return if actor.nil? || actor.tombstoned?

      withdraw_participations(actor)
      Federation::ActorDeletion.new(actor:, now: @now).call!
    end

    # Account deletion withdraws every live participation the account holds as
    # participant, and their open notices, before the actor is tombstoned: the
    # row must not stay live (docs/dev/SHARED-ACTIVITIES.md). As source owner, the
    # workouts' own destroy detaches the participants' credit rows, keeping
    # them, and withdraws the notices before the rows cascade (§6.5).
    def withdraw_participations(actor)
      WorkoutParticipation.live.where(participant_actor: actor).find_each do |participation|
        Participations::Withdraw.new(participation:, user: @user).call!
      end
      # Invitations from other instances end too; the actor's Delete tells
      # their owners (docs/dev/SHARED-ACTIVITIES.md).
      RemoteParticipation.active.where(recipient_actor: actor).find_each do |participation|
        Participations::RemoteWithdrawal.withdraw!(participation)
      end
    end

    # One workout per transaction, through the same seam as the owner's own
    # deletion: participants' credit rows are detached and kept, segment
    # counters and personal bests are refreshed, and blobs are purged later.
    # Credit rows go before the recordings they may point at.
    def delete_workouts!(limit)
      scope = @user.workouts.order(Arel.sql("CASE WHEN origin = 'import' THEN 1 ELSE 0 END"), :id)
      scope = scope.limit(limit) if limit
      scope.each { |workout| Workouts::WorkoutDeletion.new(user: @user, workout:).call! }
      !@user.workouts.exists?
    end
  end
end
