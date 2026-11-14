# frozen_string_literal: true

class RemoteAvatarsController < ApplicationController
  def show
    raise ActiveRecord::RecordNotFound unless Allure::Federation::Config.enabled?

    actor = Actor.remote.find_by(acct: params[:handle]) || Actor.remote.find_by(handle: params[:handle])
    raise ActiveRecord::RecordNotFound unless actor && !actor.tombstoned?
    raise ActiveRecord::RecordNotFound if Federation::Safety::Blocks.blocked?(actor.uri)
    raise ActiveRecord::RecordNotFound unless actor.avatar_cached?

    attachment = actor.avatar_cache
    response.headers["Cache-Control"] = "private, no-store"
    send_data attachment.download,
              filename: attachment.filename.to_s,
              type: attachment.content_type,
              disposition: "inline"
  rescue ActiveStorage::FileNotFoundError, ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
