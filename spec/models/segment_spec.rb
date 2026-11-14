# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segment do
  describe "identity" do
    it "receives a PostgreSQL UUID and exposes only its ShortUUID" do
      segment = create(:segment)

      expect(segment.uuid).to match(Allure::ShortId::UUID_PATTERN)
      expect(segment.to_param).to have_attributes(length: 22)
      expect(segment.to_param).not_to eq(segment.id.to_s)
      expect(described_class.find_by_short_id!(segment.to_param)).to eq(segment)
    end

    it "returns not found for malformed and unknown ShortUUIDs" do
      expect { described_class.find_by_short_id!("invalid") }.to raise_error(ActiveRecord::RecordNotFound)
      expect { described_class.find_by_short_id!("2222222222222222222222") }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "treats the UUID as immutable" do
      segment = create(:segment)

      expect { segment.update!(uuid: SecureRandom.uuid) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    end
  end

  describe "associations" do
    it "belongs to its owner and optionally to a sport and source workout" do
      segment = build(:segment, sport: nil, source_workout: nil)

      expect(segment).to be_valid
      expect(segment.user).to be_present
    end

    it "exposes owned segments and efforts through the related records" do
      segment = create(:segment)
      effort = create(:segment_effort, segment:)

      expect(segment.user.segments).to include(segment)
      expect(segment.sport.segments).to include(segment)
      expect(segment.segment_efforts).to include(effort)
      expect(effort.workout.segment_efforts).to include(effort)
    end

    it "nullifies the source workout when that workout is deleted" do
      source_workout = create(:workout)
      segment = create(:segment, source_workout:)

      expect { source_workout.delete }.to change { segment.reload.source_workout_id }
        .from(source_workout.id).to(nil)
    end
  end

  describe "validations" do
    it "accepts every kind supported by the table" do
      expect(Segment::KINDS.map { |kind| build(:segment, kind:) }).to all(be_valid)
    end

    it "requires a valid name and limits descriptions" do
      expect(build(:segment, name: "")).not_to be_valid
      expect(build(:segment, name: "x" * 121)).not_to be_valid
      expect(build(:segment, description: "x" * 2_001)).not_to be_valid
    end

    it "requires valid geometry, bounds, signature, distance, and tolerance" do
      expect(build(:segment, geom: geographic_factory.line_string([]))).not_to be_valid
      expect(build(:segment, bounds: [ 1.0, 2.0, 3.0 ])).not_to be_valid
      expect(build(:segment, signature: Array.new(63, 0.0))).not_to be_valid
      expect(build(:segment, distance: 0)).not_to be_valid
      expect(build(:segment, match_tolerance_meters: 4)).not_to be_valid
      expect(build(:segment, match_tolerance_meters: 101)).not_to be_valid
    end

    it "keeps routes and loops private" do
      expect(build(:segment, :route, visibility: "public")).not_to be_valid
      expect(build(:segment, :route, visibility: "followers_only")).not_to be_valid
      expect(build(:segment, :loop, visibility: "public")).not_to be_valid
      expect(build(:segment, :loop, visibility: "followers_only")).not_to be_valid
      expect(build(:segment, :route)).to be_valid
      expect(build(:segment, :loop)).to be_valid
    end

    it "rejects unknown visibility values" do
      expect(build(:segment, visibility: "unknown")).not_to be_valid
    end
  end

  describe "database invariants" do
    it "enforces the kind check" do
      expect_constraint(:kind, "other", "segments_kind")
    end

    it "enforces the visibility check below the model layer" do
      expect_constraint(:visibility, "unknown", "segments_visibility")
    end

    it "enforces positive distance" do
      expect_constraint(:distance, 0, "segments_distance")
    end

    it "enforces four bounds values" do
      expect_constraint(:bounds, [ 1.0, 2.0, 3.0 ], "segments_bounds")
    end

    it "enforces a 64-value shape signature" do
      expect_constraint(:signature, Array.new(63, 0.0), "segments_signature")
    end

    it "enforces the matching tolerance range" do
      expect_constraint(:match_tolerance_meters, 4, "segments_match_tolerance_meters")
    end

    it "enforces geometry point count" do
      expect_constraint(:geom, geographic_factory.line_string([]), "segments_geometry")
    end

    it "enforces name and description lengths" do
      expect_constraint(:name, "x" * 121, "segments_name_length")
      expect_constraint(:description, "x" * 2_001, "segments_description_length")
    end

    it "enforces non-negative ascent, descent, and counters" do
      expect_constraint(:ascent, -1, "segments_ascent")
      expect_constraint(:descent, -1, "segments_descent")
      expect_constraint(:efforts_count, -1, "segments_counts")
    end

    it "has GiST indexes for the canonical geometry and endpoints" do
      indexes = described_class.connection.indexes(:segments)

      expect(indexes.find { |index| index.columns == [ "geom" ] }.using).to eq(:gist)
      expect(indexes.find { |index| index.columns == [ "start_point" ] }.using).to eq(:gist)
      expect(indexes.find { |index| index.columns == [ "end_point" ] }.using).to eq(:gist)
    end

    it "leaves future enum values to the model lock rather than the database" do
      segment = create(:segment)

      segment.update_columns(visibility: "public")

      expect(segment.reload.visibility).to eq("public")
    end
  end

  describe "derived owner image" do
    it "enqueues the render when the course is created" do
      expect { create(:segment) }.to have_enqueued_job(Segments::RenderRouteImageJob)
    end

    it "keeps the attachment on the record and drops it with the record" do
      segment = create(:segment)
      segment.route_image.attach(io: StringIO.new("png"), filename: "segment.png", content_type: "image/png")

      expect(segment.route_image).to be_attached

      segment.destroy!

      expect(ActiveStorage::Attachment.where(record_type: "Segment", record_id: segment.id)).not_to exist
    end
  end

  describe ".run_by" do
    let(:owner) { create(:user) }
    let(:viewer) { create(:user) }
    let(:sport) { create(:sport) }

    it "keeps the courses the viewer has an effort on" do
      ran = create(:segment, user: owner, sport:, visibility: "public")
      create(:segment, user: owner, sport:, visibility: "public")
      workout = create(:workout, user: viewer, sport:)
      create(:segment_effort, segment: ran, workout:, user: viewer, sport:)

      expect(described_class.run_by(viewer)).to contain_exactly(ran)
      expect(described_class.run_by(nil)).to be_empty
    end
  end

  describe "#opted_out? and #participants_count" do
    let(:owner) { create(:user) }
    let(:segment) { create(:segment, user: owner) }

    it "excludes only athletes holding an opt-out row and counts every recorded effort, for the private counter" do
      athlete = create(:user)
      workout = create(:workout, user: athlete, sport: segment.sport)
      create(:segment_effort, segment:, workout:, user: athlete, sport: segment.sport)

      expect(segment.opted_out?(athlete)).to be(false)
      expect(segment.participants_count).to eq(1)

      create(:segment_opt_out, segment:, user: athlete)

      expect(segment.opted_out?(athlete)).to be(true)
      expect(segment.participants_count).to eq(1)
    end
  end

  describe "#viewable_by?" do
    let(:owner) { create(:user) }
    let(:segment) { create(:segment, user: owner) }

    it "stays owner-only while private" do
      expect(segment.viewable_by?(owner)).to be(true)
      expect(segment.viewable_by?(create(:user))).to be(false)
      expect(segment.viewable_by?(nil)).to be(false)
    end

    it "opens to signed-in accounts only, never anonymous, when public" do
      segment.update!(visibility: "public")

      expect(segment.viewable_by?(owner)).to be(true)
      expect(segment.viewable_by?(create(:user))).to be(true)
      expect(segment.viewable_by?(nil)).to be(false)
    end

    it "opens to accepted local followers only when followers_only" do
      segment.update!(visibility: "followers_only")
      owner_actor = create(:local_actor, user: owner)
      follower = create(:user)
      create(:local_actor, user: follower)

      expect(segment.viewable_by?(follower)).to be(false)

      create(:following, :accepted, follower_actor: follower.actor, followed_actor: owner_actor)

      expect(segment.viewable_by?(follower)).to be(true)
      expect(segment.viewable_by?(create(:user))).to be(false)
      expect(segment.viewable_by?(nil)).to be(false)
    end
  end

  describe "privacy-zone corridor acknowledgment" do
    let(:segment) { create(:segment) }

    it "blocks sharing a corridor that intersects an active zone" do
      create(:privacy_zone, user: segment.user)

      segment.visibility = "public"

      expect(segment).not_to be_valid
      expect(segment.errors.of_kind?(:base, :corridor_privacy_zone)).to be(true)
    end

    it "accepts the same corridor once acknowledged" do
      create(:privacy_zone, user: segment.user)

      segment.visibility = "public"
      segment.privacy_zone_acknowledged_at = Time.current

      expect(segment).to be_valid
    end

    it "ignores inactive zones and never questions a private corridor" do
      create(:privacy_zone, user: segment.user, active: false)

      expect(segment).to be_valid

      segment.visibility = "public"

      expect(segment).to be_valid
    end

    it "does not retroactively question an acknowledged, already-shared corridor" do
      segment.update_columns(visibility: "public", privacy_zone_acknowledged_at: Time.current)

      create(:privacy_zone, user: segment.user)

      expect(segment.reload).to be_valid
    end
  end

  describe "publication lifecycle" do
    let(:owner) { create(:user) }
    let(:segment) { create(:segment, user: owner, visibility: "public") }

    it "marks itself stale after a represented edit" do
      create(:segment_publication, segment:)
      segment.association(:active_publication).reset

      expect(segment.publication_stale?).to be(false)

      segment.update!(name: "Nouveau nom")

      expect(segment.publication_stale?).to be(true)
    end

    it "blocks a visibility restriction while a publication is active" do
      create(:segment_publication, segment:)
      segment.association(:active_publication).reset

      segment.visibility = "followers_only"

      expect(segment).not_to be_valid
      expect(segment.errors.of_kind?(:visibility, :published_restriction)).to be(true)
    end

    it "allows an opening from followers_only to public" do
      followers = create(:segment, user: owner, visibility: "followers_only")
      create(:segment_publication, segment: followers, audience: "followers")
      followers.association(:active_publication).reset

      followers.visibility = "public"

      expect(followers).to be_valid
    end

    it "allows a restriction once the publication is withdrawn" do
      publication = create(:segment_publication, segment:)
      publication.mark_deleted!
      segment.association(:active_publication).reset

      segment.visibility = "private"

      expect(segment).to be_valid
    end
  end

  describe "visibility scopes" do
    it "reads public courses, the viewer's own and followed owners' shared courses" do
      viewer = create(:user)
      owner = create(:user)
      stranger = create(:user)
      public_course = create(:segment, visibility: "public")
      own_course = create(:segment, user: viewer, visibility: "followers_only")
      shared_course = create(:segment, user: owner, visibility: "followers_only")
      private_course = create(:segment, user: viewer)
      stranger_course = create(:segment, user: stranger)
      create(:following, :accepted,
             follower_actor: create(:local_actor, user: viewer),
             followed_actor: create(:local_actor, user: owner))

      readable = described_class.readable_by(viewer)
      expect(readable).to include(public_course, own_course, shared_course)
      expect(readable).not_to include(private_course, stranger_course)

      visible = described_class.visible_to(viewer)
      expect(visible).to include(public_course, own_course, shared_course, private_course)
      expect(visible).not_to include(stranger_course)
    end

    it "ignores pending relationships" do
      viewer = create(:user)
      owner = create(:user)
      shared_course = create(:segment, user: owner, visibility: "followers_only")
      create(:following,
             follower_actor: create(:local_actor, user: viewer),
             followed_actor: create(:local_actor, user: owner))

      expect(described_class.readable_by(viewer)).not_to include(shared_course)
    end

    it "ignores courses of deactivated owners" do
      viewer = create(:user)
      owner = create(:user)
      shared_course = create(:segment, user: owner, visibility: "followers_only")
      owner.update!(deletion_requested_at: Time.current, deletion_scheduled_at: 7.days.from_now,
                    deletion_requested_by: "self")
      create(:following, :accepted,
             follower_actor: create(:local_actor, user: viewer),
             followed_actor: create(:local_actor, user: owner))

      expect(described_class.readable_by(viewer)).not_to include(shared_course)
    end

    it "serves public courses to an anonymous reader and nothing through visible_to" do
      public_course = create(:segment, visibility: "public")
      create(:segment, user: create(:user), visibility: "followers_only")

      expect(described_class.readable_by(nil)).to contain_exactly(public_course)
      expect(described_class.visible_to(nil)).to be_empty
    end
  end

  private

  def expect_constraint(column, value, name)
    segment = create(:segment)

    expect do
      described_class.transaction(requires_new: true) { segment.update_column(column, value) }
    end
      .to raise_error(ActiveRecord::StatementInvalid, /#{name}/)
  end
end
