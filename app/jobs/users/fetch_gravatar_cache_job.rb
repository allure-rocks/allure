# frozen_string_literal: true

module Users
  # Fetches the account's Gravatar server-side and caches it as an attachment
  # (DESIGN.md §9.3). The browser only ever talks to this instance; when no
  # Gravatar exists (d=404) or the fetch fails, nothing is attached and the
  # avatar chain silently falls through to the generated avatar.
  class FetchGravatarCacheJob < ApplicationJob
    GRAVATAR_HOST = "www.gravatar.com"
    GRAVATAR_SIZE = 256
    MAX_BYTES = 2.megabytes

    queue_as :default

    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user&.gravatar_opt_in?

      response = fetch(gravatar_url(user))
      return unless response.is_a?(Net::HTTPSuccess)
      return unless response.content_type.to_s.start_with?("image/")
      return if response.body.bytesize > MAX_BYTES

      user.gravatar_cache.attach(
        io: StringIO.new(response.body),
        filename: "gravatar-#{user.id}.img",
        content_type: response.content_type
      )
    rescue StandardError => error
      Rails.error.report(error, handled: true)
    end

    private

    def gravatar_url(user)
      hash = Digest::MD5.hexdigest(user.email_address.to_s.strip.downcase)
      URI::HTTPS.build(host: GRAVATAR_HOST, path: "/avatar/#{hash}", query: "s=#{GRAVATAR_SIZE}&d=404")
    end

    def fetch(url)
      Net::HTTP.start(url.host, url.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.get(url.request_uri)
      end
    end
  end
end
