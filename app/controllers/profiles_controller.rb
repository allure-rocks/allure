# frozen_string_literal: true

class ProfilesController < ApplicationController
  include Pagy::Method

  # The account's portrait and publication journal, shown to members only
  # (docs/dev/ACCESS.md). The listing follows Workouts::PublicationPolicy:
  # public publications serve every account, followers publications serve the
  # owner and accepted local followers while restricted federation is enabled.
  # Drafts and scheduled publications live on /workouts and /me, never on this
  # URL.
  def show
    @user = User.find_by(username: params[:username].to_s.downcase)
    raise ActiveRecord::RecordNotFound unless @user
    # Hidden for the deletion window (PLAN_ACCOUNT.md §4.2).
    raise ActiveRecord::RecordNotFound if @user.deletion_scheduled?

    # While federation is off no actor is provisioned for a visit: an account
    # without one has no relationship yet, and following it provisions it.
    @actor = Allure::Federation::Config.enabled? ? Federation::ActorProvisioner.new(user: @user).call! : @user.actor
    @following = current_user&.actor && @actor &&
      Following.active.find_by(follower_actor: current_user.actor, followed_actor: @actor)

    # One publication per workout, the one this reader is served
    # (docs/dev/PUBLISHING.md), so a follower never counts a workout twice.
    publications = WorkoutPublication.served_to(current_user).where(workout_id: @user.workouts.select(:id))
    @profile_account = @user
    @shared_statistics = Profiles::SharedStatistics.new(user: @user, viewer: current_user).call
    @shared_records = Profiles::SharedRecords.new(user: @user, viewer: current_user).call
    @journal = Profiles::Journal.new(scope: publications, viewer: current_user, sport: params[:sport], period: params[:period])
    scope = @journal.relation.includes({ route_image_attachment: :blob }, workout: [ :sport, :user, :active_publications ])
    @pagy, publications = pagy(scope, limit: 12)
    @items = @journal.items_for(publications)
    @reaction_targets = @items.map(&:record)
    @comment_targets = @reaction_targets
  rescue Federation::ActorProvisioner::IdentityConflict
    raise ActiveRecord::RecordNotFound
  end
end
