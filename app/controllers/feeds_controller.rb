# frozen_string_literal: true

# The personal feed. Viewing publications requires an account: a visitor is
# redirected to sign-in by `require_authentication` before this action runs,
# so the controller only ever renders the signed-in stream — followed accounts
# plus remote notes they hold an entitlement for, with the instance's public
# publications joining through the URL-driven Public switch.
class FeedsController < ApplicationController
  include Pagy::Method

  def show
    @actor = Federation::ActorProvisioner.new(user: current_user).call!
    @follows_anyone = Following.accepted_following_of(@actor).exists?
    @include_public = include_public?(@follows_anyone)
    feed = Federation::FollowingFeed.new(actor: @actor, include_public: @include_public)
    @pagy, rows = pagy(feed.relation, limit: 12)
    @items = feed.items_for(rows)
    @reaction_targets = @items.map(&:record)
    @comment_targets = @reaction_targets
  rescue Federation::ActorProvisioner::IdentityConflict
    raise ActiveRecord::RecordNotFound
  end

  private

  # An explicit choice always wins; with no `public` parameter, an account
  # that follows nobody sees the instance's public publications instead of an
  # empty page. The switch writes an explicit value, so the auto default only
  # applies to a bare /feed.
  def include_public?(follows_anyone)
    requested = case params[:public].to_s
    when "1", "true" then true
    when "0", "false" then false
    end
    requested.nil? ? !follows_anyone : requested
  end
end
