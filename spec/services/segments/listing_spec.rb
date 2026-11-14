# frozen_string_literal: true

require "rails_helper"

# PLAN_SEGMENTS.md §8.2: the board follows the reader. An effort appears for a
# viewer who may see the course and read a publication of the workout that
# shares its route, unless the athlete opted out or a privacy zone touches the
# corridor.
RSpec.describe Segments::Listing do
  let(:owner) { create(:user) }
  let(:athlete) { create(:user) }
  let(:stranger) { create(:user) }
  let(:sport) { create(:sport) }

  around do |example|
    original = ENV["FEDERATION_RESTRICTED_ENABLED"]
    ENV["FEDERATION_RESTRICTED_ENABLED"] = "true"
    example.run
  ensure
    ENV["FEDERATION_RESTRICTED_ENABLED"] = original
  end

  # Sharing is forced underneath the model's sharing gates so eligibility can
  # be exercised for each visibility level.
  def course(visibility: "public")
    segment = create(:segment, user: owner, sport:)
    segment.update_column(:visibility, visibility)
    segment.reload
  end

  def publish(workout, followers: false, route: true)
    profile = followers ? build(:publishing_profile, :followers, user: workout.user) : build(:publishing_profile, user: workout.user)
    profile.settings = profile.settings.merge("route" => route)
    publication = build(:workout_publication, workout:, publishing_profile: profile, status: "active")
    publication.save!
    workout.reload
    publication
  end

  def follow(follower, followed)
    create(:following, :accepted, follower_actor: actor_for(follower), followed_actor: actor_for(followed))
  end

  def actor_for(user) = user.reload.actor || create(:actor, :local, user:)

  def run!(segment, user: athlete, **publication)
    workout = create(:workout, user:, sport:)
    publish(workout, **publication) unless publication.delete(:unpublished)
    create(:segment_effort, segment:, workout:, user:, sport:)
  end

  def sees?(segment, viewer, scope: "everyone")
    described_class.for_segment(segment, viewer:, scope:).exists?
  end

  it "shows a public publication sharing the route to every member who sees the course" do
    segment = course
    run!(segment)

    expect(sees?(segment, stranger)).to be(true)
    expect(sees?(segment, owner)).to be(true)
    expect(sees?(segment, athlete)).to be(true)
  end

  it "shows a followers publication to the athlete's followers only, whatever the course visibility" do
    segment = course(visibility: "public")
    run!(segment, followers: true)
    follower = create(:user)
    follow(follower, athlete)

    expect(sees?(segment, follower)).to be(true)
    expect(sees?(segment, athlete)).to be(true)
    expect(sees?(segment, stranger)).to be(false)
    expect(sees?(segment, owner)).to be(false)
  end

  it "keeps a followers publication for local followers with restricted federation off" do
    segment = course
    run!(segment, followers: true)
    follower = create(:user)
    follow(follower, athlete)
    ENV["FEDERATION_RESTRICTED_ENABLED"] = "false"

    expect(sees?(segment, follower)).to be(true)
  end

  it "never reveals a passage whose publication hides the route" do
    segment = course
    run!(segment, route: false)

    expect(sees?(segment, stranger)).to be(false)
    expect(sees?(segment, athlete)).to be(false)
  end

  it "ignores the retired segment setting of an older snapshot" do
    segment = course
    effort = run!(segment)
    publication = effort.workout.active_publications.first
    legacy = publication.profile_snapshot
    legacy["settings"] = legacy.fetch("settings").merge("segment" => false)
    WorkoutPublication.where(id: publication.id).update_all(profile_snapshot: legacy)

    expect(sees?(segment, stranger)).to be(true)
  end

  it "shows nothing without a live publication" do
    segment = course
    effort = run!(segment)
    expect(sees?(segment, stranger)).to be(true)

    effort.workout.active_publications.first.mark_deleted!
    expect(sees?(segment, stranger)).to be(false)

    other = course
    run!(other, unpublished: true)
    expect(sees?(other, athlete)).to be(false)
  end

  it "shows nothing to a viewer who cannot see the course" do
    segment = course(visibility: "followers_only")
    run!(segment)
    owner_follower = create(:user)
    follow(owner_follower, owner)

    expect(sees?(segment, owner_follower)).to be(true)
    expect(sees?(segment, stranger)).to be(false)
  end

  it "keeps private courses, routes, loops and inactive courses without a board" do
    private_segment = course(visibility: "private")
    run!(private_segment, user: owner)
    route = create(:segment, :route, user: owner, sport:)
    run!(route, user: owner)
    inactive = course
    inactive.update_column(:active, false)
    run!(inactive)

    expect(sees?(private_segment, owner)).to be(false)
    expect(sees?(route, owner)).to be(false)
    expect(sees?(inactive, stranger)).to be(false)
  end

  it "excludes an athlete whose privacy zone touches the corridor, never the course owner's zone" do
    segment = course
    run!(segment)
    create(:privacy_zone, user: owner, latitude: 45.0719, longitude: 6.4083, radius_meters: 1000)
    expect(sees?(segment, stranger)).to be(true)

    # The factory segment runs 45.0710,6.4074 → 45.0728,6.4092.
    create(:privacy_zone, user: athlete, latitude: 45.0719, longitude: 6.4083, radius_meters: 1000)
    expect(sees?(segment, stranger)).to be(false)
  end

  it "excludes an athlete who left the board until they rejoin" do
    segment = course
    run!(segment)

    exclusion = create(:segment_opt_out, segment:, user: athlete)
    expect(sees?(segment, stranger)).to be(false)

    exclusion.destroy!
    expect(sees?(segment, stranger)).to be(true)
  end

  it "narrows the following view to the accounts the viewer follows and the viewer" do
    segment = course
    run!(segment)
    run!(segment, user: stranger)

    expect(described_class.for_segment(segment, viewer: stranger, scope: "following").pluck(:user_id)).to eq([ stranger.id ])

    follow(stranger, athlete)
    expect(described_class.for_segment(segment, viewer: stranger, scope: "following").pluck(:user_id))
      .to contain_exactly(stranger.id, athlete.id)
  end

  it "counts the distinct athletes of the viewer's board, never a hidden effort" do
    segment = course
    run!(segment)
    run!(segment)
    run!(segment, user: owner, unpublished: true)
    run!(segment, user: create(:user), route: false)
    followers_only = create(:user)
    run!(segment, user: followers_only, followers: true)
    opted_out = create(:user)
    run!(segment, user: opted_out)
    create(:segment_opt_out, segment:, user: opted_out)
    zoned = create(:user)
    run!(segment, user: zoned)
    create(:privacy_zone, user: zoned, latitude: 45.0719, longitude: 6.4083, radius_meters: 1000)

    expect(described_class.participants_count(segment, viewer: stranger)).to eq(1)

    follow(stranger, followers_only)
    expect(described_class.participants_count(segment, viewer: stranger)).to eq(2)
    expect(described_class.participants_counts([ segment.id, course.id ], viewer: stranger)).to eq(segment.id => 2)
    expect(described_class.participants_count(segment, viewer: nil)).to eq(0)
  end

  it "covers a page of courses in one scope and nothing without a viewer" do
    first = course
    second = course
    hidden = course(visibility: "private")
    workout = create(:workout, user: athlete, sport:)
    publish(workout)
    [ first, second, hidden ].each { create(:segment_effort, segment: it, workout:, user: athlete, sport:) }

    ids = described_class.for_segments([ first.id, second.id, hidden.id ], viewer: stranger).distinct.pluck(:segment_id)

    expect(ids).to contain_exactly(first.id, second.id)
    expect(described_class.for_segments([ first.id ], viewer: nil)).to be_empty
  end
end
