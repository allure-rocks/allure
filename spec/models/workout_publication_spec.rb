# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutPublication do
  describe "identity" do
    it "derives a ShortUUID and permanent object URI from its UUID" do
      publication = create(:workout_publication)

      expect(publication.uuid).to match(Allure::ShortId::UUID_PATTERN)
      expect(publication.to_param).to have_attributes(length: 22)
      # See the equivalent note in workout_spec: a substring check against the
      # integer id is flaky because the base-57 alphabet includes 2-9.
      expect(publication.to_param).to eq(Allure::ShortId.encode(publication.uuid))
      expect(publication.to_param).not_to eq(publication.id.to_s)
      expect(described_class.find_by_short_id!(publication.to_param)).to eq(publication)
      expect(publication.object_uri)
        .to eq(Allure::Federation.config.workout_publication_uri(publication.to_param))
    end

    it "rejects an object URI that is not derived from its UUID" do
      publication = build(:workout_publication, object_uri: "https://elsewhere.test/trail/invalid")

      expect(publication).not_to be_valid
      expect(publication.errors[:object_uri]).to be_present
    end
  end

  describe "associations and persistence" do
    it "belongs to the source workout and profile owner" do
      publication = create(:workout_publication)

      expect(publication.workout.workout_publications).to include(publication)
      expect(publication.publishing_profile.user.workout_publications).to include(publication)
    end

    it "snapshots profile settings when none are supplied" do
      profile = create(:publishing_profile)
      publication = create(:workout_publication, workout: create(:workout, user: profile.user), publishing_profile: profile)

      expect(publication.profile_snapshot).to eq(
        "audience" => profile.audience,
        "name" => profile.name,
        "settings" => profile.settings
      )
    end

    it "treats a missing basemap setting as enabled and an explicit nil as disabled" do
      legacy = build(:workout_publication, profile_snapshot: {
        "audience" => "public", "name" => "Public profile", "settings" => { "route" => true }
      })
      explicit_off = build(:workout_publication, profile_snapshot: {
        "audience" => "public", "name" => "Public profile", "settings" => { "route" => true, "basemap" => nil }
      })

      expect(legacy.basemap_enabled?).to be(true)
      expect(explicit_off.basemap_enabled?).to be(false)
    end

    it "keeps publication identity and sanitized data immutable" do
      publication = create(:workout_publication)

      expect { publication.update!(object_uri: "https://elsewhere.test/new") }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { publication.update!(profile_snapshot: {}) }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    it "rejects private fields from the sanitized representation" do
      publication = build(:workout_publication)
      publication.representation = publication.representation.merge("notes" => "private")

      expect(publication).not_to be_valid
      expect(publication.errors[:representation]).to be_present
    end

    it "rejects unknown published record markers" do
      publication = build(:workout_publication)
      publication.representation = publication.representation.merge("record_types" => %w[BOGUS])

      expect(publication).not_to be_valid
      expect(publication.errors[:representation]).to be_present
    end

    it "accepts a bounded shared device and rejects malformed ones" do
      workout = create(:workout)
      actor = create(:local_actor, user: workout.user)
      profile = create(:publishing_profile, user: workout.user)
      base = build(:workout_publication).representation

      bounded = build(:workout_publication, workout:, actor:, publishing_profile: profile,
                      representation: base.merge("device" => "Garmin Edge 530"))
      expect(bounded).to be_valid

      too_long = build(:workout_publication, workout:, actor:, publishing_profile: profile,
                       representation: base.merge("device" => "x" * 121))
      too_long.valid?
      expect(too_long.errors[:representation]).to be_present

      blank = build(:workout_publication, workout:, actor:, publishing_profile: profile,
                    representation: base.merge("device" => ""))
      blank.valid?
      expect(blank.errors[:representation]).to be_present
    end

    it "accepts a presence commute flag and rejects a stored false" do
      workout = create(:workout)
      actor = create(:local_actor, user: workout.user)
      profile = create(:publishing_profile, user: workout.user)
      base = build(:workout_publication).representation

      flagged = build(:workout_publication, workout:, actor:, publishing_profile: profile,
                      representation: base.merge("commute" => true))
      expect(flagged).to be_valid

      stored_false = build(:workout_publication, workout:, actor:, publishing_profile: profile,
                           representation: base.merge("commute" => false))
      stored_false.valid?
      expect(stored_false.errors[:representation]).to be_present
    end

    it "accepts a presence closed-comments flag and reads the thread state from it" do
      workout = create(:workout)
      actor = create(:local_actor, user: workout.user)
      profile = create(:publishing_profile, user: workout.user)
      base = build(:workout_publication).representation

      stored_false = build(:workout_publication, workout: Workout.find(workout.id), actor:, publishing_profile: profile,
                                                 representation: base.merge("comments_closed" => false))
      stored_false.valid?
      expect(stored_false.errors[:representation]).to be_present

      open = create(:workout_publication, workout:, actor:, publishing_profile: profile)
      expect(open.comments_open?).to be(true)
      workout.update!(comments_closed_at: Time.current)
      expect(open.comments_open?).to be(false)

      closed = build(:workout_publication, workout: create(:workout, user: workout.user), actor:,
                                           publishing_profile: profile, comments_closed: true)
      expect(closed).to be_valid
      expect(closed.comments_closed_by_profile?).to be(true)
      expect(closed.comments_open?).to be(false)
    end

    it "exposes publication-owned sanitized attachments" do
      expect(described_class.reflect_on_attachment(:gpx)).to be_present
      expect(described_class.reflect_on_attachment(:route_image)).to be_present
      expect(described_class.reflect_on_attachment(:original_file)).to be_nil
    end
  end

  describe "lifecycle" do
    it "permits one active publication per workout" do
      publication = create(:workout_publication)

      expect { create(:workout_publication, workout: publication.workout) }
        .to raise_error(ActiveRecord::RecordInvalid, /has already been taken/)
    end

    it "deletes terminally without deleting the source workout" do
      publication = create(:workout_publication)
      workout = publication.workout

      publication.mark_deleted!

      expect(publication).to be_deleted
      expect(publication.deleted_at).to be_present
      expect(workout.reload).to be_present
      expect(workout.workout_publications).to include(publication)
      expect { publication.update!(status: "active") }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "delayed publishing" do
    it "defaults published_at to the planned moment and stays invisible" do
      planned = 3.days.from_now
      publication = create(:workout_publication, :scheduled, scheduled_for: planned)

      expect(publication).to be_scheduled
      expect(publication.published_at).to be_within(1.second).of(planned)
      expect(publication.workout.scheduled_publications.first).to eq(publication)
      expect(publication.workout.active_publications.first).to be_nil
      expect(described_class.active).not_to include(publication)
      expect(described_class.publicly_visible).not_to include(publication)
    end

    it "requires a planned moment and forbids a deletion timestamp" do
      missing = build(:workout_publication, :scheduled, scheduled_for: nil)
      expect(missing).not_to be_valid
      expect(missing.errors[:scheduled_for]).to be_present

      inconsistent = build(:workout_publication, :scheduled, deleted_at: Time.current)
      expect(inconsistent).not_to be_valid
      expect(inconsistent.errors[:deleted_at]).to be_present
    end

    it "requires a source workout while scheduled" do
      publication = build(:workout_publication, :scheduled)
      publication.workout = nil

      expect(publication).not_to be_valid
      expect(publication.errors[:workout]).to be_present
    end

    it "permits one live or scheduled publication per workout" do
      active = create(:workout_publication)
      expect { create(:workout_publication, :scheduled, workout: active.workout) }
        .to raise_error(ActiveRecord::RecordInvalid, /has already been taken/)

      scheduled = create(:workout_publication, :scheduled)
      expect { create(:workout_publication, workout: scheduled.workout) }
        .to raise_error(ActiveRecord::RecordInvalid, /has already been taken/)
    end

    it "activates in place, rewriting published_at to the actual instant" do
      planned = 2.days.from_now
      publication = create(:workout_publication, :scheduled, scheduled_for: planned)
      activated_at = planned + 5.minutes

      publication.activate!(at: activated_at)

      expect(publication).to be_active
      expect(publication.published_at).to be_within(1.second).of(activated_at)
      expect(publication.scheduled_for).to be_within(1.second).of(planned)
      expect(publication.reload.workout.active_publications.first).to eq(publication)
      expect(publication.workout.scheduled_publications.first).to be_nil
    end

    it "leaves non-scheduled publications untouched when activation is attempted" do
      active = create(:workout_publication)
      active.activate!(at: Time.current)
      expect(active.reload.status).to eq("active")

      deleted = create(:workout_publication)
      deleted.mark_deleted!
      deleted.activate!(at: Time.current)
      expect(deleted.reload.status).to eq("deleted")
    end

    it "cancels terminally without any federation trace" do
      publication = create(:workout_publication, :scheduled)

      publication.mark_deleted!

      expect(publication).to be_deleted
      expect(publication.workout.reload.scheduled_publications.first).to be_nil
      expect(publication.outbox_events).to be_empty
      expect { publication.update!(status: "active") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "rejects transitions outside the lifecycle" do
      publication = create(:workout_publication)
      expect { publication.update!(status: "scheduled", scheduled_for: 1.day.from_now) }
        .to raise_error(ActiveRecord::RecordInvalid)

      publication.mark_deleted!
      expect { publication.update!(status: "active") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "Slice 3 retained identity" do
    it "retains its local actor and rejects actor changes" do
      publication = create(:workout_publication)

      expect(publication.actor).to be_present
      expect(publication.actor).to be_local
      expect(publication.actor.user_id).to eq(publication.workout.user_id)
      expect { publication.update!(actor: create(:local_actor)) }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
    end

    it "rejects a remote or tombstoned retained actor" do
      publication = build(:workout_publication, actor: create(:actor))
      expect(publication).not_to be_valid

      owned = create(:workout_publication)
      owned.actor.tombstone!
      expect(owned.reload).not_to be_valid
    end

    it "requires a source workout while active" do
      publication = build(:workout_publication)
      publication.workout = nil
      expect(publication).not_to be_valid
      expect(publication.errors[:workout]).to be_present
    end

    it "allows a deleted publication to retain identity without its source" do
      publication = create(:workout_publication)
      publication.mark_deleted!
      workout = publication.workout

      workout.destroy!

      retained = described_class.find(publication.id)
      expect(retained).to be_deleted
      expect(retained.workout_id).to be_nil
      expect(retained.actor).to be_present
      expect(retained.object_uri).to eq(publication.object_uri)
    end

    it "prevents an active publication from losing its source at the database boundary" do
      publication = create(:workout_publication)

      expect {
        described_class.where(id: publication.id).update_all(workout_id: nil)
      }.to raise_error(ActiveRecord::StatementInvalid, /workout_publications_active_requires_source/)
    end

    it "uses its retained actor for its publication document" do
      publication = create(:workout_publication)

      expect(publication.publication_document["attributedTo"]).to eq(publication.actor.uri)
    end
  end

  # `visible_to` is the SQL projection behind the profile listing; it must
  # never drift from the browser branch of Workouts::PublicationPolicy
  # (PLAN_M5 §13.2). Each case compares the scope's rows with the policy's
  # verdict for the same viewer.
  describe "visible_to" do
    def visible_ids(scope)
      scope.pluck(:id).sort
    end

    def policy_ids(user, publications)
      principal = Workouts::PublicationPrincipal.browser(user)
      publications.select do |publication|
        Workouts::PublicationPolicy.new(publication:, principal:).allowed?
      end.map(&:id).sort
    end

    it "matches the browser publication policy across relationship states and restricted modes" do
      owner = create(:user)
      owner_actor = create(:local_actor, user: owner)
      public_publication = create(
        :workout_publication, workout: create(:workout, user: owner), actor: owner_actor
      )
      followers_publication = create(
        :workout_publication, :with_followers,
        workout: create(:workout, user: owner), actor: owner_actor
      )
      publications = [ public_publication, followers_publication ]

      unrelated = create(:user)
      follower = create(:user)
      create(:following, :accepted, follower_actor: create(:local_actor, user: follower), followed_actor: owner_actor)
      pending = create(:user)
      create(:following, follower_actor: create(:local_actor, user: pending), followed_actor: owner_actor)
      undone = create(:user)
      create(:following, :undone, follower_actor: create(:local_actor, user: undone), followed_actor: owner_actor)

      [ false, true ].each do |restricted|
        allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(restricted)

        [ nil, owner, unrelated, follower, pending, undone ].each do |viewer|
          expect(visible_ids(described_class.visible_to(viewer)))
            .to eq(policy_ids(viewer, publications)),
                "viewer=#{viewer&.username.inspect} restricted=#{restricted}"
        end
      end
    end

    it "fails closed for a tombstoned viewer actor" do
      viewer = create(:user)
      create(:local_actor, user: viewer).tombstone!
      publication = create(:workout_publication)

      expect(described_class.visible_to(viewer)).to be_empty
      expect(described_class.visible_to(viewer)).not_to include(publication)
    end

    it "excludes scheduled and deleted publications for their owner" do
      owner = create(:user)
      profile = create(:publishing_profile, user: owner)
      scheduled = create(
        :workout_publication, :scheduled, workout: create(:workout, user: owner), publishing_profile: profile
      )
      deleted = create(
        :workout_publication, workout: create(:workout, user: owner), publishing_profile: profile
      )
      deleted.mark_deleted!

      expect(described_class.visible_to(owner)).not_to include(scheduled, deleted)
    end
  end

  # The board's route rule (PLAN_SEGMENTS.md §8.2): the frozen profile shares
  # the route and the route was not redacted.
  describe "route_shared" do
    it "keeps publications whose frozen profile shares the route" do
      publication = create(:workout_publication)

      expect(described_class.route_shared).to include(publication)
    end

    it "excludes publications whose profile does not share the route" do
      owner = create(:user)
      profile = build(:publishing_profile, user: owner)
      profile.settings = profile.settings.merge("route" => false)
      publication = create(
        :workout_publication, workout: create(:workout, user: owner), publishing_profile: profile
      )

      expect(described_class.route_shared).not_to include(publication)
    end

    it "excludes publications whose route was redacted" do
      publication = create(:workout_publication, route_metadata: { "redacted" => true })

      expect(described_class.route_shared).not_to include(publication)
    end
  end

  describe "audience precedence" do
    it "keeps the SQL rank in step with AUDIENCE_PRECEDENCE" do
      ranks = described_class::AUDIENCE_PRECEDENCE.map do |audience|
        described_class.connection.select_value(
          "SELECT #{described_class::AUDIENCE_RANK_SQL} FROM (SELECT '#{audience}'::text AS audience) AS workout_publications"
        )
      end

      expect(ranks).to eq(described_class::AUDIENCE_PRECEDENCE.map { |audience| described_class.audience_rank(audience) })
    end
  end
end
