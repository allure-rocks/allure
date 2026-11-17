# frozen_string_literal: true

module FederationNoteFixtures
  SEGMENT_SHORT_ID = Allure::ShortId.encode("00000000-0000-0000-0000-0000000000aa")
  SEGMENT_OBJECT_URI = "https://remote.example/api/v1/segment/#{SEGMENT_SHORT_ID}"

  def federation_note_activity(overrides = {})
    {
      "id" => "https://remote.example/api/v1/trail/abc/activities/create-1",
      "type" => "Create",
      "actor" => "https://remote.example/users/demo",
      "object" => {
        "id" => "https://remote.example/api/v1/trail/abc",
        "type" => "Note",
        "attributedTo" => "https://remote.example/users/demo",
        "name" => "Morning hike",
        "content" => "Morning hike<br>A short description",
        "startTime" => "2026-08-26T12:00:00Z",
        "published" => "2026-08-26T12:00:00Z",
        "location" => { "type" => "Place", "longitude" => 6.4, "latitude" => 45.0 },
        "to" => [ "https://www.w3.org/ns/activitystreams#Public" ],
        "cc" => [ "https://remote.example/users/demo/followers" ],
        "tag" => [
          { "type" => "Note", "name" => "category", "content" => "Hiking" },
          { "type" => "Note", "name" => "distance", "content" => "23064.640055m" }
        ],
        "attachment" => [
          { "type" => "Document", "mediaType" => "application/xml+gpx",
            "url" => "https://remote.example/api/v1/trail/abc/media/gpx" }
        ]
      },
      "to" => [ "https://www.w3.org/ns/activitystreams#Public" ],
      "cc" => [ "https://remote.example/users/demo/followers" ]
    }.merge(overrides)
  end

  # A remote reader's comment (docs/dev/COMMENTS.md): addressed to the
  # thread host only, answering a publication or a comment.
  def federation_comment_activity(in_reply_to:, to:, id: "https://remote.example/api/v1/comment/c1",
                                  content: "Belle sortie !<br>On y retourne ?", actor: "https://remote.example/users/demo")
    {
      "id" => "#{id}/activities/create-1",
      "type" => "Create",
      "actor" => actor,
      "object" => {
        "id" => id,
        "type" => "Note",
        "attributedTo" => actor,
        "inReplyTo" => in_reply_to,
        "content" => content,
        "published" => "2026-10-05T09:12:44Z",
        "to" => Array(to),
        "cc" => []
      },
      "to" => Array(to),
      "cc" => []
    }
  end

  def federation_delete_activity(object: "https://remote.example/api/v1/trail/abc", overrides: {})
    {
      "id" => "https://remote.example/api/v1/trail/abc/activities/delete-1",
      "type" => "Delete",
      "actor" => "https://remote.example/users/demo",
      "object" => object
    }.merge(overrides)
  end

  def federation_segment_activity(overrides = {})
    {
      "id" => "#{SEGMENT_OBJECT_URI}/activities/create-1",
      "type" => "Create",
      "actor" => "https://remote.example/users/demo",
      "object" => {
        "id" => SEGMENT_OBJECT_URI,
        "type" => "Note",
        "attributedTo" => "https://remote.example/users/demo",
        "name" => "Col du Test",
        "content" => "Col du Test<br>Le versant nord",
        "published" => "2026-08-26T12:00:00Z",
        "location" => { "type" => "Place", "longitude" => 6.4, "latitude" => 45.0 },
        "to" => [ "https://www.w3.org/ns/activitystreams#Public" ],
        "cc" => [ "https://remote.example/users/demo/followers" ],
        "tag" => [
          { "type" => "Note", "name" => "category", "content" => "Cycling" },
          { "type" => "Note", "name" => "sport_slug", "content" => "cycling" },
          { "type" => "Note", "name" => "segment_kind", "content" => "segment" },
          { "type" => "Note", "name" => "distance", "content" => "2500.000000m" },
          { "type" => "Note", "name" => "elevation_gain", "content" => "180.000000m" },
          { "type" => "Note", "name" => "match_tolerance", "content" => "25.000000m" }
        ],
        "attachment" => [
          { "type" => "Document", "mediaType" => "application/xml+gpx",
            "url" => "#{SEGMENT_OBJECT_URI}/media/gpx" },
          { "type" => "Image", "mediaType" => "image/png",
            "url" => "#{SEGMENT_OBJECT_URI}/media/route-image" }
        ]
      },
      "to" => [ "https://www.w3.org/ns/activitystreams#Public" ],
      "cc" => [ "https://remote.example/users/demo/followers" ]
    }.merge(overrides)
  end

  def federation_segment_delete_activity(object: SEGMENT_OBJECT_URI, overrides: {})
    {
      "id" => "#{SEGMENT_OBJECT_URI}/activities/delete-1",
      "type" => "Delete",
      "actor" => "https://remote.example/users/demo",
      "object" => object
    }.merge(overrides)
  end
end

RSpec.configure do |config|
  config.include FederationNoteFixtures
end
