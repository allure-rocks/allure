# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Serializers::WorkoutNote do
  let(:user) { create(:user) }
  let(:workout) do
    create(
      :workout,
      user:,
      title: "Morning <ride>",
      description: "A private-looking description"
    )
  end
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:publication) do
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    publish_workout!(user:, workout:, profile:)
  end

  def attach_blob(filename, bytes)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(bytes), filename:, content_type: "image/png"
    )
  end

  def attach_route_image_variants(target)
    light = attach_blob("route-light.png", "\x89PNG\r\n\x1A\nlight".b)
    dark = attach_blob("route-dark.png", "\x89PNG\r\n\x1A\ndark".b)
    target.route_image.attach(light)
    target.route_image_dark.attach(dark)
    WorkoutPublication.where(id: target.id).update_all(
      sanitized_route_image_blob_id: light.id,
      sanitized_route_image_dark_blob_id: dark.id
    )
    target.reload
  end

  it "serializes the sanitized publication as a Wanderer-compatible Note" do
    note = described_class.new(publication:, actor_uri: user.actor_uri).call

    expect(note).to include(
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => publication.object_uri,
      "type" => "Note",
      "attributedTo" => user.actor_uri,
      "name" => "Morning <ride>",
      "startTime" => "2026-08-23T06:00:00Z",
      "url" => "#{Allure::Federation.config.base_url}/workouts/#{workout.to_param}",
      "published" => publication.published_at.utc.iso8601
    )
    expect(note.dig("location", "type")).to eq("Place")
    expect(note.dig("location", "longitude")).to eq(6.4074)
    expect(note.dig("location", "latitude")).to eq(45.071)
    expect(note["content"]).to include("Morning &lt;ride&gt;")
    expect(note["content"]).to include("A private-looking description")
    expect(note["to"]).to eq([ Federation::Serializers::WorkoutNote::PUBLIC_AUDIENCE ])
    expect(note["cc"]).to eq([ "#{user.actor_uri}/followers" ])
    expect(note["tag"]).to include(
      include("name" => "category", "content" => workout.sport.label),
      include("name" => "distance", "content" => "250.000000m"),
      include("name" => "elevation_gain", "content" => "12.000000m"),
      include("name" => "duration", "content" => "60.000000m")
    )
  end

  it "uses the filtered location when the route itself is not published" do
    profile = create(
      :publishing_profile,
      :without_endpoint_masks,
      user:,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "route" => false, "route_image" => false, "mask_start" => false, "mask_finish" => false
      )
    )
    publication = publish_workout!(user:, workout:, profile:)

    note = described_class.new(publication:, actor_uri: user.actor_uri).call

    expect(note["location"]).to include("longitude" => 6.4074, "latitude" => 45.071)
    expect(note).not_to have_key("attachment")
  end

  it "does not include the public audience for followers publications" do
    profile = create(:publishing_profile, :followers, :without_endpoint_masks, user:)
    publication = create(:workout_publication, workout:, publishing_profile: profile)

    note = described_class.new(publication:, actor_uri: user.actor_uri).call

    expect(note["to"]).to eq([ "#{user.actor_uri}/followers" ])
    expect(note["cc"]).to eq([])
    expect(note.values.flatten).not_to include(Federation::Serializers::WorkoutNote::PUBLIC_AUDIENCE)
  end

  it "carries the shared recording device as one dedicated tag" do
    workout.update!(source: "Garmin Edge 530")
    profile = create(
      :publishing_profile,
      :without_endpoint_masks,
      user:,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "device" => true, "mask_start" => false, "mask_finish" => false
      )
    )
    publication = publish_workout!(user:, workout:, profile:)

    note = described_class.new(publication:, actor_uri: user.actor_uri).call

    expect(note["tag"]).to include(include("name" => "device", "content" => "Garmin Edge 530"))
  end

  it "omits the device tag when the profile keeps it off" do
    note = described_class.new(publication:, actor_uri: user.actor_uri).call

    expect(note["tag"]).not_to include(include("name" => "device"))
  end

  it "carries a shared commute as one presence tag" do
    workout.update!(commute: true)
    profile = create(
      :publishing_profile,
      :without_endpoint_masks,
      user:,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "commute" => true, "mask_start" => false, "mask_finish" => false
      )
    )
    commute_publication = publish_workout!(user:, workout:, profile:)

    note = described_class.new(publication: commute_publication, actor_uri: user.actor_uri).call

    expect(note["tag"]).to include(include("name" => "commute", "content" => "true"))
  end

  it "carries a shared weather summary as short SI tags, never the hourly series" do
    create(:workout_weather, workout:)
    profile = create(
      :publishing_profile,
      :without_endpoint_masks,
      user:,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "weather" => true, "mask_start" => false, "mask_finish" => false
      )
    )
    weather_publication = publish_workout!(user:, workout: workout.reload, profile:)

    note = described_class.new(publication: weather_publication, actor_uri: user.actor_uri).call

    expect(weather_publication.representation["weather"]).not_to include("series", "samples")
    expect(note["tag"]).to include(
      include("name" => "weather_condition", "content" => "partly_cloudy"),
      include("name" => "weather_temperature", "content" => "11.2,15.8,10.4"),
      include("name" => "weather_wind_exposure", "content" => "0.420,0.310,0.270,0.80")
    )
    parsed = Allure::Weather::NoteTags.decode(note["tag"].to_h { [ it["name"], it["content"] ] })
    expect(parsed["temperature_max"]).to eq(15.8)
  end

  it "omits the weather tags when the profile keeps them off" do
    create(:workout_weather, workout:)

    note = described_class.new(publication:, actor_uri: user.actor_uri).call

    expect(note["tag"].map { it["name"] }).not_to include(a_string_starting_with("weather"))
  end

  it "omits the commute tag when the profile keeps it off or the workout is not one" do
    workout.update!(commute: true)
    note = described_class.new(publication:, actor_uri: user.actor_uri).call
    expect(note["tag"]).not_to include(include("name" => "commute"))

    other_workout = create(:workout, user:, commute: false)
    create(:track_segment, workout: other_workout)
    profile = create(
      :publishing_profile,
      :custom,
      user:,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "commute" => true, "mask_start" => false, "mask_finish" => false
      )
    )
    other_publication = publish_workout!(user:, workout: other_workout, profile:)
    other_note = described_class.new(publication: other_publication, actor_uri: user.actor_uri).call

    expect(other_note["tag"]).not_to include(include("name" => "commute"))
  end

  it "announces comments closed by the profile and says nothing while they are open" do
    note = described_class.new(publication:, actor_uri: user.actor_uri).call
    expect(note["tag"]).not_to include(include("name" => "comments"))

    other_workout = create(:workout, user:)
    create(:track_segment, workout: other_workout)
    profile = create(
      :publishing_profile,
      :custom,
      user:,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "comments" => false, "mask_start" => false, "mask_finish" => false
      )
    )
    closed_publication = publish_workout!(user:, workout: other_workout, profile:)
    closed_note = described_class.new(publication: closed_publication, actor_uri: user.actor_uri).call

    expect(closed_publication.representation["comments_closed"]).to be(true)
    expect(closed_note["tag"]).to include(include("name" => "comments", "content" => "closed"))
  end

  it "advertises the dark route image after the light one" do
    attach_route_image_variants(publication)

    note = described_class.new(publication:, actor_uri: user.actor_uri).call
    images = note["attachment"].select { |attachment| attachment["type"] == "Image" }

    expect(images.map { |attachment| attachment["url"] }).to eq([
      "#{publication.object_uri}/media/route-image",
      "#{publication.object_uri}/media/route-image-dark"
    ])
    expect(images.last["allure:theme"]).to eq("dark")
  end

  it "advertises only the light image when the dark variant is absent" do
    light = attach_blob("route-light.png", "\x89PNG\r\n\x1A\nlight".b)
    publication.route_image.attach(light)
    WorkoutPublication.where(id: publication.id).update_all(sanitized_route_image_blob_id: light.id)
    publication.reload

    note = described_class.new(publication:, actor_uri: user.actor_uri).call
    images = note["attachment"].select { |attachment| attachment["type"] == "Image" }

    expect(images.length).to eq(1)
    expect(images.first).not_to have_key("allure:theme")
  end
end
