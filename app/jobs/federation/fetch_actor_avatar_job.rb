# frozen_string_literal: true

require "stringio"

module Federation
  # Caches a remote actor's avatar locally (docs/dev/FEDERATION.md). The browser only
  # ever talks to this instance; a failed fetch stays silent and the avatar
  # component falls back to the generated art.
  class FetchActorAvatarJob < ApplicationJob
    MAX_BYTES = 1.megabyte
    MAX_DIMENSION = 2048
    IMAGE_TYPES = {
      "\x89PNG\r\n\x1a\n".b => "image/png",
      "\xFF\xD8\xFF".b => "image/jpeg",
      "GIF87a".b => "image/gif",
      "GIF89a".b => "image/gif"
    }.freeze

    queue_as :federation_media
    limits_concurrency key: ->(actor_id) { actor_id }, duration: 5.minutes

    def perform(actor_id)
      actor = Actor.remote.find_by(id: actor_id)
      return unless actor&.avatar_url.present? && !actor.tombstoned?
      return if Safety::Blocks.blocked?(actor.uri)

      response = Transport::Client.new.get(actor.avatar_url, headers: { "Accept" => "image/*" })
      return unless response.status.between?(200, 299)

      body = response.body.to_s.b
      return if body.empty? || body.bytesize > MAX_BYTES

      content_type = detect_type(body)
      return unless content_type
      return unless valid_dimensions?(body)

      actor.avatar_cache.attach(
        io: StringIO.new(body),
        filename: "actor-#{actor.id}.img",
        content_type:,
        identify: false
      )
      actor.update_column(:avatar_cached_at, Time.current)
    rescue Transport::Client::ResponseTooLarge, Transport::Client::ResponseTimeout,
           Transport::Client::NetworkError, Transport::SsrfGuard::UnsafeUri => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, actor_id: })
    end

    private

    def detect_type(body)
      IMAGE_TYPES.each { |signature, type| return type if body.start_with?(signature) }
      return "image/webp" if body.bytesize > 12 && body[0, 4] == "RIFF" && body[8, 4] == "WEBP"

      nil
    end

    def valid_dimensions?(body)
      image = Vips::Image.new_from_buffer(body, "")
      image.width <= MAX_DIMENSION && image.height <= MAX_DIMENSION
    rescue Vips::Error
      false
    end
  end
end
