# frozen_string_literal: true

module Users
  # The deletion window (docs/dev/ACCOUNT.md): a request deactivates the
  # account at once and schedules its deletion GRACE later; cancelling within
  # the window restores it. Nothing federates during the window, because a
  # withdrawn publication can never be restored. Once the purge has started
  # the deletion can no longer be cancelled.
  class DeletionSchedule
    GRACE = 7.days

    class NotAllowed < StandardError; end

    def initialize(user:, now: Time.current)
      @user = user
      @now = now
    end

    # `keep_session` is the session that asked: it stays signed in on the
    # deactivated page; every other session closes.
    def schedule!(by:, keep_session: nil)
      raise NotAllowed, "the operator account cannot be deleted from the web" if @user.instance_operator?
      raise NotAllowed, "a deletion is already scheduled" if @user.deletion_scheduled?

      User.transaction do
        @user.lock!
        @user.update!(deletion_requested_at: @now, deletion_scheduled_at: @now + GRACE, deletion_requested_by: by)
        sessions = @user.sessions
        sessions = sessions.where.not(id: keep_session.id) if keep_session
        sessions.destroy_all
      end
      AccountMailer.deletion_scheduled(@user).deliver_later
      true
    end

    def cancel!
      raise NotAllowed, "no deletion is scheduled" unless @user.deletion_scheduled?

      cancelled = @user.with_lock do
        next false if @user.deletion_started?

        @user.update!(deletion_requested_at: nil, deletion_scheduled_at: nil, deletion_requested_by: nil)
        true
      end
      raise NotAllowed, "the deletion has started" unless cancelled

      AccountMailer.deletion_cancelled(@user).deliver_later
      true
    end
  end
end
