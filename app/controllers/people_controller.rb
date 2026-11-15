# frozen_string_literal: true

# The signed-in relationship hub (docs/dev/FEDERATION.md, PLAN_PEOPLE.md): following,
# followers, requests to decide, outgoing requests, and the two discovery
# surfaces — name search and suggestions. Relationships between accounts of
# this instance never depend on FEDERATION_ENABLED: while it is off, the hub
# lists local accounts only and refuses a remote target before any discovery
# request.
class PeopleController < ApplicationController
  include Pagy::Method

  TABS = %w[following followers requests].freeze
  PEOPLE_PER_PAGE = 20
  # A search box sends one request per pause in typing. The bound is generous
  # enough for a person, tight enough that nobody walks the directory.
  SEARCH_REQUESTS_PER_MINUTE = 30

  rate_limit to: SEARCH_REQUESTS_PER_MINUTE, within: 1.minute, only: :search,
             by: -> { current_user.id }, with: -> { head :too_many_requests }

  def index
    @federation_enabled = Allure::Federation::Config.enabled?
    @local_actor = Federation::ActorProvisioner.new(user: current_user).call!
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "following"

    @following_scope = within_reach(Following.accepted_following_of(@local_actor), :followed_actor)
    @followers_scope = within_reach(Following.accepted_followers_of(@local_actor), :follower_actor)
    @incoming_scope = within_reach(Following.where(followed_actor: @local_actor, status: "pending"), :follower_actor)
    @outgoing_scope = within_reach(Following.where(follower_actor: @local_actor, status: "pending"), :followed_actor)

    @following_count = @following_scope.count
    @followers_count = @followers_scope.count
    @requests_count = @incoming_scope.count + @outgoing_scope.count

    case @tab
    when "followers"
      @pagy, @people = pagy(@followers_scope.includes(:follower_actor).order(:id), limit: PEOPLE_PER_PAGE)
    when "requests"
      @pagy, @incoming_requests = pagy(@incoming_scope.includes(:follower_actor).order(:id), limit: PEOPLE_PER_PAGE)
      @outgoing_requests = @outgoing_scope.includes(:followed_actor).order(:id).limit(PEOPLE_PER_PAGE)
    else
      @pagy, @people = pagy(@following_scope.includes(followed_actor: :user).order(:id), limit: PEOPLE_PER_PAGE)
      @suggestions = People::Suggestions.new(viewer: current_user).call
    end
  end

  # PLAN_PEOPLE.md §3: the live suggestions fragment. HTML, because each row
  # carries a follow form; the Stimulus controller swaps it into the dropdown.
  def search
    set_no_store
    results = People::Search.new(
      viewer: current_user, query: params[:q], federation_enabled: Allure::Federation::Config.enabled?
    ).call
    render partial: "people/search_results", locals: { results: }
  end

  def resolve
    target = params[:target].to_s
    raise Federation::TargetResolver::InvalidTarget, "target is required" if target.blank?

    resolver = Federation::TargetResolver.new
    unless Allure::Federation::Config.enabled? || resolver.local_target?(target)
      raise Federation::TargetResolver::InvalidTarget, "federation is disabled"
    end

    actor = resolver.call!(target)
    if actor.local?
      redirect_to profile_path(actor.user.username)
    else
      redirect_to remote_profile_path(actor.acct.presence || actor.handle)
    end
  rescue Federation::TargetResolver::InvalidTarget
    redirect_to people_path, alert: t("people.search.invalid")
  end

  private

  # Relationships with remote accounts stay stored while federation is off,
  # but are dormant: their profiles are unreachable and nothing is delivered.
  def within_reach(scope, counterpart)
    return scope if Allure::Federation::Config.enabled?

    scope.where(counterpart => Actor.local)
  end

  def set_no_store
    response.headers["Cache-Control"] = "no-store"
  end
end
