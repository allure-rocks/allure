# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::Suggestions do
  let(:viewer) { create(:user, username: "viewer") }
  let(:workout) { create(:workout, user: viewer) }

  def suggestions = described_class.new(viewer:).call

  def discoverable_user(username)
    user = create(:user, username:, display_name: username.titleize, discoverable: "members")
    provision(user)
    user
  end

  def provision(user) = Federation::ActorProvisioner.new(user:).call!

  before { provision(viewer) }

  it "suggests an account that reacted to one of the viewer's workouts" do
    reactor = discoverable_user("marie")
    create(:reaction, workout:, actor: provision(reactor))

    suggestion = suggestions.sole

    expect(suggestion.user).to eq(reactor)
    expect(suggestion.reason).to eq(:interaction)
  end

  it "suggests an account that commented on one of the viewer's workouts" do
    commenter = discoverable_user("paul")
    create(:comment, workout:, actor: provision(commenter))

    expect(suggestions.sole.reason).to eq(:interaction)
  end

  it "suggests an account the instance detected together with the viewer" do
    companion = discoverable_user("joan")
    create(:workout_participation, workout:, participant_actor: provision(companion), origin: "detection",
                                   kind: "link", participant_workout: create(:workout, user: companion))

    expect(suggestions.sole.reason).to eq(:together)
  end

  it "suggests an athlete who shares a course with the viewer" do
    rider = discoverable_user("eva")
    segment = create(:segment, user: viewer)
    create(:segment_effort, workout:, user: viewer, segment:, started_at: 1.day.ago)
    create(:segment_effort, workout: create(:workout, user: rider), user: rider, segment:, started_at: 1.day.ago)

    expect(suggestions.sole.reason).to eq(:leaderboard)
  end

  it "never suggests an account that is not discoverable" do
    reactor = create(:user, username: "hidden")
    create(:reaction, workout:, actor: provision(reactor))

    expect(suggestions).to be_empty
  end

  it "never suggests the viewer" do
    viewer.update!(discoverable: "members")
    create(:reaction, workout:, actor: provision(viewer))

    expect(suggestions).to be_empty
  end

  it "never suggests an account the viewer already follows" do
    reactor = discoverable_user("marie")
    create(:reaction, workout:, actor: provision(reactor))
    create(:following, :accepted, follower_actor: provision(viewer), followed_actor: provision(reactor),
                                  uri: "https://remote.example/activities/follow-out")

    expect(suggestions).to be_empty
  end

  it "never suggests a dismissed account again" do
    reactor = discoverable_user("marie")
    create(:reaction, workout:, actor: provision(reactor))
    PeopleSuggestionDismissal.create!(user: viewer, actor: provision(reactor))

    expect(suggestions).to be_empty
  end

  it "never suggests a blocked remote account" do
    remote = create(:actor, uri: "https://remote.example/users/demo", acct: "demo@remote.example")
    create(:reaction, workout:, actor: remote)
    FederationActorBlock.create!(actor_uri: remote.uri)

    expect(suggestions).to be_empty
  end

  it "ignores a reaction older than the window" do
    reactor = discoverable_user("marie")
    create(:reaction, workout:, actor: provision(reactor), created_at: 120.days.ago)

    expect(suggestions).to be_empty
  end
end
