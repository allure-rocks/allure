# frozen_string_literal: true

require "digest"
require "net/http"
require "uri"

namespace :virtual do
  # Regenerates the world map images under public/virtual_worlds/ (PLAN_VIRTUAL.md
  # §2.1). Operator opt-in: the application never downloads an image at runtime,
  # and the generated files are not committed (Zwift's artwork is not ours to
  # redistribute), so a checkout without them draws the ordinary basemap.
  #
  # Every world comes from Zwift's own map CDN, the source the MIT-licensed
  # zwift-data package names for each world. Each download is pinned by the
  # SHA-256 of the file, because Zwift rewrites a map in place under the same
  # name: a mismatch means the artwork changed, and the task refuses to write
  # anything until it has been reviewed. The generated file is named after the
  # pinned digest, so a new map gets a new URL and no browser keeps the old one
  # behind the production cache headers.
  #
  #   dip rails virtual:world_images
  #   dip rails virtual:world_images WORLD=paris
  desc "Download the pinned Zwift world maps and rewrite the WebP copies"
  task world_images: :environment do
    require "vips"

    # `rotate` turns the stored artwork north-up: Zwift draws Makuri Islands,
    # France, Paris and Scotland with north to the right, so the catalogued
    # rectangles line up only after a quarter turn.
    sources = {
      "watopia" => { file: "MiniMap_Watopia_2.png",
                     sha256: "f499174289f728d549e1cab0a354248e719f057ff895dec52cdc804039433177" },
      "richmond" => { file: "MiniMap_Richmond.png",
                      sha256: "69e6f13febfa1d1fe9f889366ecb18b780e3344edfb7ddfa328811085477298a" },
      "london" => { file: "MiniMap_London.png",
                    sha256: "2fe1b8c8ba7eaafb5ea44a5cca652e34194ce37bdbd39e5f8e491871c2dae46e" },
      "new_york" => { file: "MiniMap_NewYork_2.png",
                      sha256: "a93a82f7825298dcc6634330368602971585cf288e021870829ef7d381036ddf" },
      "innsbruck" => { file: "MiniMap_Innsbruck.png",
                       sha256: "34f9344e5e27a46a7d0d98da135f48d5593ebccfed3d78a096a967ae56bfa8f5" },
      "bologna" => { file: "MiniMap_Bologna.png",
                     sha256: "8ac0c598fca4758f05f08ee1d61c6727e892c6cd3c346f6086a6b9103afa781b" },
      "yorkshire" => { file: "MiniMap_Yorkshire.png",
                       sha256: "6dad558c26b63bdd5e0157a1ea937e10f1af3326cc445ddf60913514d6006ec9" },
      "crit_city" => { file: "MiniMap_CritCity.png",
                       sha256: "973dcdcc33bff7f2bab44c486d2a11073f236fca56cd56d531119bd2f06fa39c" },
      "makuri_islands" => { file: "MiniMap_Japan.png",
                            sha256: "445cf44a79da025b92d9be0c3bba42f130b38f061f66e6907c595a3a9396d7e9",
                            rotate: :d270 },
      "france" => { file: "MiniMap_France.png",
                    sha256: "c7bd7593283c65242064d697892ceb67297decd984a28772f128a578d9668471",
                    rotate: :d270 },
      "paris" => { file: "MiniMap_Paris_2.png",
                   sha256: "c5f46d676e1e813e5bb6d4ed2057cee0605122dd006b04bde9276d1150341c78",
                   rotate: :d270 },
      "scotland" => { file: "MiniMap_Scotland.png",
                      sha256: "c35e210f1746bc4e0c639258968eb5236b1da5d21159c18b5d3c384ae57f2ee5",
                      rotate: :d270 }
    }.freeze
    expected = sources.to_h { |key, source| [ key, "#{key}-#{source[:sha256][0, 8]}.webp" ] }

    base = "https://cdn.zwift.com/static/images/maps"
    destination = Rails.root.join("public/virtual_worlds/zwift")
    max_side = 4096
    only = ENV["WORLD"].presence
    written = 0
    fetch = lambda do |uri|
      response = Net::HTTP.get_response(uri)
      abort "virtual:world_images: #{uri} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    Allure::Virtual::Platforms.fetch("zwift").venues.each do |venue|
      basemap = venue.basemap or next
      next if only && venue.key != only

      source = sources.fetch(venue.key) do
        abort "virtual:world_images: #{venue.key} has no pinned source; add one to the task."
      end
      body = fetch.call(URI("#{base}/#{source[:file]}"))
      digest = Digest::SHA256.hexdigest(body)
      unless digest == source[:sha256]
        abort <<~MESSAGE
          virtual:world_images: #{source[:file]} changed (sha256 #{digest}).
          Review the new artwork, then update the pinned digest in this task and
          the catalogue's image name (virtual_worlds/zwift/#{venue.key}-#{digest[0, 8]}.webp).
        MESSAGE
      end

      image = Vips::Image.new_from_buffer(body, "")
      image = image.rot(source[:rotate]) if source[:rotate]
      scale = [ max_side.to_f / [ image.width, image.height ].max, 1.0 ].min
      image = image.resize(scale) if scale < 1.0
      path = destination.join(expected.fetch(venue.key))
      image.webpsave(path.to_s, Q: 82, effort: 6, strip: true)
      puts "#{path.relative_path_from(Rails.root)} #{image.width}x#{image.height} #{File.size(path) / 1024} KB"
      written += 1
    end

    abort "virtual:world_images: no world named #{only} in the catalogue." if only && written.zero?

    # The directory is generated wholesale. A full run also removes what no
    # pinned source produces, so a previous map never ships forever; a filtered
    # run leaves the other worlds' files alone.
    if only.nil?
      stale = destination.glob("*.webp").map { |path| path.basename.to_s } - expected.values
      stale.each do |name|
        destination.join(name).delete
        puts "removed #{File.join("public/virtual_worlds/zwift", name)}"
      end
    end
  end
end
