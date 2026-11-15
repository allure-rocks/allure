# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PublicationPolicy do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:workout) { create(:workout, user: owner) }
  let(:representation) do
    {
      "sport_slug" => workout.sport.slug,
      "started_at" => workout.started_at.iso8601(6),
      "metrics" => { "distance" => 250.0 },
      "track" => {
        "type" => "FeatureCollection",
        "features" => [
          {
            "type" => "Feature",
            "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
            "properties" => { "segment_index" => 0 }
          }
        ]
      },
      "chart" => [ { "distance" => 0.0, "elapsed_time" => 0.0, "elevation" => 100.0 } ]
    }
  end
  let(:public_profile) { create(:publishing_profile, user: owner) }
  let(:public_publication) do
    create(:workout_publication, workout:, publishing_profile: public_profile, representation:)
  end
  let(:followers_workout) { create(:workout, user: owner) }
  let(:followers_profile) { create(:publishing_profile, :followers, user: owner) }
  let(:followers_publication) do
    create(
      :workout_publication,
      workout: followers_workout,
      publishing_profile: followers_profile,
      representation: representation.merge(
        "sport_slug" => followers_workout.sport.slug,
        "started_at" => followers_workout.started_at.iso8601(6)
      )
    )
  end
  let(:owner_actor) { create(:local_actor, user: owner) }
  let(:remote_actor) { create(:actor) }

  def allowed?(publication, principal, resource: :workout)
    described_class.new(publication:, principal:).allowed?(resource:)
  end

  describe "browser principals" do
    it "denies an anonymous browser and allows signed-in browsers on a public publication" do
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.anonymous)).to be(false)
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.browser(owner))).to be(true)
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.browser(other_user))).to be(true)
    end

    # docs/dev/FEDERATION.md: the local followers audience does not depend on the
    # restricted-federation switch.
    it "serves followers publications to the owner and accepted local followers only, restricted federation off" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      local_follower = create(:user)
      local_follower_actor = create(:local_actor, user: local_follower)
      create(:following, :accepted, follower_actor: local_follower_actor, followed_actor: owner_actor)

      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.anonymous)).to be(false)
      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.browser(owner))).to be(true)
      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.browser(local_follower))).to be(true)
      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.browser(other_user))).to be(false)
    end
  end

  describe "protocol principals" do
    it "serves a public publication to unsigned and signed protocol requests" do
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.protocol(nil))).to be(true)
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.protocol(remote_actor))).to be(true)
    end

    it "denies followers publications to an unsigned protocol request" do
      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.protocol(nil))).to be(false)
    end
  end

  describe "remote actors" do
    it "allows a signed unrelated actor to read a public publication" do
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.protocol(remote_actor))).to be(true)
    end

    it "denies followers publications to a promoted remote follower while restricted federation is off" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      remote_actor.update!(capability_profile: "restricted_fetch")
      create(:following, :accepted, follower_actor: remote_actor, followed_actor: owner_actor)

      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.protocol(remote_actor))).to be(false)
    end

    it "rejects pending, rejected, and undone remote followings" do
      [ :pending, :rejected, :undone ].each do |state|
        actor = create(:actor)
        following = create(:following, follower_actor: actor, followed_actor: owner_actor)
        following.reject! if state == :rejected
        following.undo! if state == :undone

        expect(allowed?(followers_publication, Workouts::PublicationPrincipal.protocol(actor))).to be(false)
      end
    end

    it "rejects a tombstoned accepted follower" do
      create(:following, :accepted, follower_actor: remote_actor, followed_actor: owner_actor)
      remote_actor.tombstone!

      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.protocol(remote_actor))).to be(false)
    end
  end

  describe "restricted followers access" do
    before do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      create(:following, :accepted, follower_actor: remote_actor, followed_actor: owner_actor)
    end

    it "allows the owner and an accepted local follower" do
      local_follower = create(:user)
      local_follower_actor = create(:local_actor, user: local_follower)
      create(:following, :accepted, follower_actor: local_follower_actor, followed_actor: owner_actor)

      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.browser(owner))).to be(true)
      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.browser(local_follower))).to be(true)
      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.protocol(local_follower_actor))).to be(true)
    end

    it "denies an unrelated browser" do
      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.browser(other_user))).to be(false)
    end

    it "allows a promoted accepted remote follower" do
      remote_actor.update!(capability_profile: "restricted_fetch")

      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.protocol(remote_actor))).to be(true)
    end

    it "denies an unpromoted accepted remote follower" do
      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.protocol(remote_actor))).to be(false)
    end

    it "denies an unrelated promoted remote actor" do
      unrelated = create(:actor, capability_profile: "restricted_shared_inbox")

      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.protocol(unrelated))).to be(false)
    end
  end

  describe "publication state" do
    it "rejects deleted and absent publications" do
      public_publication.mark_deleted!

      expect(allowed?(public_publication, Workouts::PublicationPrincipal.protocol(nil))).to be(false)
      expect(allowed?(nil, Workouts::PublicationPrincipal.protocol(nil))).to be(false)
    end
  end

  describe "snapshot resources" do
    it "allows only resources retained by the publication" do
      principal = Workouts::PublicationPrincipal.browser(other_user)

      expect(allowed?(public_publication, principal, resource: :workout)).to be(true)
      expect(allowed?(public_publication, principal, resource: :analysis)).to be(true)
      expect(allowed?(public_publication, principal, resource: :track)).to be(true)
      expect(allowed?(public_publication, principal, resource: :map)).to be(true)
      expect(allowed?(public_publication, principal, resource: :chart)).to be(true)
      expect(allowed?(public_publication, principal, resource: :gpx)).to be(false)
      expect(allowed?(public_publication, principal, resource: :route_image)).to be(false)
    end

    it "denies omitted metric, route, and chart snapshots" do
      sparse = create(
        :workout_publication,
        workout: create(:workout),
        representation: {
          "sport_slug" => workout.sport.slug,
          "started_at" => workout.started_at.iso8601(6),
          "metrics" => {}
        }
      )
      principal = Workouts::PublicationPrincipal.browser(other_user)

      expect(allowed?(sparse, principal, resource: :analysis)).to be(false)
      expect(allowed?(sparse, principal, resource: :track)).to be(false)
      expect(allowed?(sparse, principal, resource: :chart)).to be(false)
    end

    it "requires both endpoint settings and immutable attachments for media" do
      profile = create(
        :publishing_profile,
        user: owner,
        settings: PublishingProfile::DEFAULT_SETTINGS.merge("gpx" => true, "route_image" => true)
      )
      gpx_blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("gpx"), filename: "route.gpx", content_type: "application/gpx+xml"
      )
      route_image_blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("png"), filename: "route.png", content_type: "image/png"
      )
      publication = create(
        :workout_publication,
        workout: create(:workout, user: owner),
        publishing_profile: profile,
        representation:,
        sanitized_gpx_blob_id: gpx_blob.id,
        sanitized_route_image_blob_id: route_image_blob.id
      )
      publication.gpx.attach(gpx_blob)
      publication.route_image.attach(route_image_blob)
      principal = Workouts::PublicationPrincipal.browser(other_user)

      expect(allowed?(publication, principal, resource: :gpx)).to be(true)
      expect(allowed?(publication, principal, resource: :route_image)).to be(true)
      expect(allowed?(publication, principal, resource: :media)).to be(true)
    end
  end

  # PLAN_COMMENTS.md §4.1: the audience gates of :workout, the owner included,
  # while the snapshot's profile and the owner's live switch keep it open.
  describe "comments" do
    it "lets the owner, members, and protocol actors comment on an open public publication" do
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.browser(owner), resource: :comment)).to be(true)
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.browser(other_user), resource: :comment))
        .to be(true)
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.protocol(remote_actor), resource: :comment))
        .to be(true)
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.anonymous, resource: :comment)).to be(false)
    end

    it "closes the thread through the snapshot or the live switch" do
      closed_by_profile = create(:workout_publication, workout: create(:workout, user: owner),
                                                       publishing_profile: public_profile, comments_closed: true)
      principal = Workouts::PublicationPrincipal.browser(other_user)

      expect(allowed?(closed_by_profile, principal, resource: :comment)).to be(false)
      expect(allowed?(closed_by_profile, principal)).to be(true)

      public_publication.workout.update!(comments_closed_at: Time.current)
      expect(allowed?(public_publication, principal, resource: :comment)).to be(false)
      expect(allowed?(public_publication, Workouts::PublicationPrincipal.browser(owner), resource: :comment))
        .to be(false)
    end

    it "follows the followers audience" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      local_follower = create(:user)
      local_follower_actor = create(:local_actor, user: local_follower)
      create(:following, :accepted, follower_actor: local_follower_actor, followed_actor: owner_actor)

      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.browser(local_follower), resource: :comment))
        .to be(true)
      expect(allowed?(followers_publication, Workouts::PublicationPrincipal.browser(other_user), resource: :comment))
        .to be(false)
    end
  end
end
