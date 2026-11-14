# frozen_string_literal: true

FactoryBot.define do
  factory :segment_publication do
    segment
    actor do
      owner = segment&.user
      owner ? (owner.actor || association(:local_actor, user: owner)) : association(:local_actor)
    end
    audience { segment&.visibility == "followers_only" ? "followers" : "public" }
    source_fingerprint { segment ? segment.publication_fingerprint : "0" * 64 }
    route_metadata do
      segment ? { "bounds" => segment.bounds, "segments_count" => 1 } : { "bounds" => [ 45.0, 6.4, 45.1, 6.5 ], "segments_count" => 1 }
    end
    representation do
      representation = {
        "name" => segment&.name || "Col du Test",
        "kind" => "segment",
        "distance" => (segment&.distance || 250.0).to_f,
        "match_tolerance" => segment&.match_tolerance_meters || 25,
        "track" => {
          "type" => "FeatureCollection",
          "features" => [
            {
              "type" => "Feature",
              "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4074, 45.071 ], [ 6.4092, 45.0728 ] ] },
              "properties" => { "segment_index" => 0 }
            }
          ]
        },
        "location" => { "longitude" => 6.4074, "latitude" => 45.071 }
      }
      representation["sport_slug"] = segment.sport.slug if segment&.sport
      representation["ascent"] = segment.ascent.to_f if segment && !segment.ascent.nil?
      representation["descent"] = segment.descent.to_f if segment && !segment.descent.nil?
      representation["average_grade"] = segment.average_grade.to_f if segment && !segment.average_grade.nil?
      representation
    end

    trait :with_gpx do
      after(:create) do |publication|
        publication.gpx.attach(
          io: StringIO.new("<?xml version=\"1.0\"?><gpx version=\"1.1\"><trk><trkseg><trkpt lat=\"45.071\" lon=\"6.4074\"/><trkpt lat=\"45.0728\" lon=\"6.4092\"/></trkseg></trk></gpx>"),
          filename: "segment-#{publication.to_param}.gpx",
          content_type: "application/gpx+xml"
        )
        publication.class.where(id: publication.id).update_all(sanitized_gpx_blob_id: publication.gpx.blob.id)
        publication.reload
      end
    end
  end
end
