# frozen_string_literal: true

# A cached remote account. Resolution happens through the authenticated
# /people search, so this page never performs an outbound fetch; an unknown
# handle is a 404.
class RemoteProfilesController < ApplicationController
  include Pagy::Method

  def show
    raise ActiveRecord::RecordNotFound unless Allure::Federation::Config.enabled?

    @actor = Actor.remote.find_by(acct: params[:handle]) || Actor.remote.find_by(handle: params[:handle])
    raise ActiveRecord::RecordNotFound unless @actor && !@actor.tombstoned?
    raise ActiveRecord::RecordNotFound if Federation::Safety::Blocks.blocked?(@actor.uri)

    @following = current_user&.actor && Following.active.find_by(follower_actor: current_user.actor, followed_actor: @actor)
    @profile_account = @actor
    @journal = Profiles::Journal.new(scope: notes_scope, viewer: current_user, sport: params[:sport], period: params[:period])
    scope = @journal.relation.includes({ actor: :avatar_cache_attachment }, attachments: :blob)
    @pagy, notes = pagy(scope, limit: 12)
    @items = @journal.items_for(notes)
    @reaction_targets = notes.to_a
    @comment_targets = @reaction_targets
    @pagy_segments, @remote_segments = pagy(segments_scope, limit: 12, page_key: "segments_page")
    return unless current_user && @actor.avatar_url.present? && !@actor.avatar_cached?

    Federation::FetchActorAvatarJob.perform_later(@actor.id)
  end

  private

  # Only notes this local account was admitted for; remote profiles never
  # expose another account's delivered copies (docs/dev/FEDERATION.md).
  def notes_scope
    actor = current_user&.actor
    return RemoteNote.none unless actor

    RemoteNote.active
      .where(actor: @actor)
      .joins(:recipients)
      .merge(RemoteNoteRecipient.active.where(recipient_actor: actor))
  end

  # Entitled courses follow the same account scoping as notes
  # (docs/dev/SEGMENTS-FEDERATION.md).
  def segments_scope
    actor = current_user&.actor
    return RemoteSegment.none unless actor

    RemoteSegment.active
      .where(actor: @actor)
      .joins(:recipients)
      .merge(RemoteSegmentRecipient.active.where(recipient_actor: actor))
      .includes(:actor)
      .order(published_at: :desc, id: :desc)
  end
end
