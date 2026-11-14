# frozen_string_literal: true

class AvatarsController < ApplicationController
  def show
    user = User.find_by(username: params[:username].to_s.downcase)
    attachment = user&.avatar_source
    raise ActiveRecord::RecordNotFound unless attachment

    response.headers["Cache-Control"] = "private, no-store"
    send_data attachment.download,
              filename: attachment.filename.to_s,
              type: attachment.content_type,
              disposition: "inline"
  rescue ActiveStorage::FileNotFoundError, ArgumentError
    raise ActiveRecord::RecordNotFound
  end
end
