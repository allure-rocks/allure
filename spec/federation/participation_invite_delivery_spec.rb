# frozen_string_literal: true

require "rails_helper"

# A remote invitation as the owner's instance sends it (PLAN_TOGETHER.md §7):
# only to an account that holds the workout's publication and follows the
# owner, only when the publication shares the credited figures, as an Invite
# addressed to that account alone, riding on the publication.
RSpec.describe "Remote participation invitations" do
  let(:owner) { create(:user) }
  let!(:owner_actor) { create(:local_actor, user: owner) }
  let(:workout) { create(:workout, user: owner) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }
  let(:publication) { publish_workout!(user: owner, workout:, profile:) }
  let(:create_event) { FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri) }
  let!(:remote) do
    create(:actor, uri: "https://remote.example/users/paul", inbox_url: "https://remote.example/inbox",
                   capability_profile: "public_only")
  end
  let(:client) { instance_double(Federation::Transport::Client) }
  let(:resolver) { instance_double(Federation::ActorResolver) }
  let(:accepted) { Federation::Transport::Client::Response.new(202, {}, "", URI("https://remote.example/inbox")) }

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    create(:following, :accepted, follower_actor: remote, followed_actor: owner_actor)
    allow(client).to receive(:validate_url)
    allow(client).to receive(:post).and_return(accepted)
    allow(resolver).to receive(:resolve) { |uri| Actor.find_by!(uri:) }
    allow_any_instance_of(Federation::TargetResolver).to receive(:call!) { |_resolver, target| Actor.find_by!(uri: target) }
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer).to receive(:call)
      .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "no browser")
  end

  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def expand(event) = Federation::Outbox::Expander.new(event:, actor_resolver: resolver, client:).call!

  def deliver_all(event)
    event.reload.deliveries.map do |delivery|
      Federation::Delivery::Deliver.new(delivery:, client:, now: Time.current).call!
      delivery.reload
    end
  end

  def publication_delivered!
    Workouts::RenderPublicationRouteImageJob.perform_now(publication)
    expand(create_event)
    deliver_all(create_event)
  end

  def invite(target: remote.uri) = Participations::Propose.new(user: owner, workout:, target:).call!

  def invite_event(participation) = FederationOutboxEvent.find_by!(activity_uri: participation.wire_activity_uri)

  it "invites an account holding the publication with an Invite addressed to it alone" do
    publication_delivered!

    participation = invite

    expect(participation).to have_attributes(participant_actor: remote, kind: "credit", origin: "invitation",
                                             workout_publication: publication)
    expect(participation.owner_confirmed_at).to be_present
    event = invite_event(participation)
    expect(event).to have_attributes(activity_type: "Invite", subject_type: "WorkoutPublication",
                                     workout_publication_id: publication.id, object_uri: owner_actor.uri)
    expect(event.payload).to include(
      "type" => "Invite", "actor" => owner_actor.uri, "object" => publication.object_uri,
      "target" => remote.uri, "to" => [ remote.uri ], "cc" => []
    )
    expect(event.payload["_allure_participation"]).to eq(
      "sport_slug" => workout.sport.slug, "started_at" => workout.started_at.utc.iso8601
    )
    expect(event.payload.to_json).not_to include("distance", "coordinates")

    expand(event)
    deliveries = deliver_all(event)
    expect(deliveries.flat_map { it.recipients.authorized.pluck(:actor_uri) }).to eq([ remote.uri ])
    expect(deliveries).to all(be_delivered)
  end

  it "is idempotent for a live pair and terminal after a refusal" do
    publication_delivered!
    participation = invite

    expect { invite }.not_to change(FederationOutboxEvent.where(activity_type: "Invite"), :count)

    participation.update!(declined_at: Time.current)
    expect { invite }.to raise_error(Participations::Propose::NotAllowed, /refusal/)
  end

  it "replaces an invitation riding on a publication that is gone" do
    publication_delivered!
    stale = invite
    stale.update_columns(workout_publication_id: nil, participant_confirmed_at: Time.current)

    renewed = invite

    expect(renewed).not_to eq(stale)
    expect(stale.reload).to be_withdrawn
    expect(renewed.workout_publication).to eq(publication)
  end

  it "refuses an account that does not hold the publication" do
    publication

    expect { invite }.to raise_error(Participations::Propose::NotAllowed, /hold/)
  end

  it "refuses an account that does not follow the owner" do
    publication_delivered!
    Following.where(follower_actor: remote).delete_all

    expect { invite }.to raise_error(Participations::Propose::NotAllowed, /follow/)
  end

  it "refuses a publication hiding a credited figure" do
    profile.update!(settings: profile.settings.merge("metrics" => PublishingProfile::METRIC_KEYS - [ "ascent" ]))
    publication_delivered!

    expect { invite }.to raise_error(Participations::Propose::NotAllowed, /figures/)
  end

  it "never delivers once the publication is withdrawn" do
    publication_delivered!
    participation = invite
    Workouts::PublicationWithdrawal.new(user: owner, workout:, publication:, reason: "deleted").persist!

    expand(invite_event(participation))

    expect(invite_event(participation).reload.deliveries.flat_map { it.recipients.authorized.pluck(:actor_uri) }).to be_empty
    expect(client).not_to have_received(:post).with(anything, hash_including(body: a_string_including("Invite")))
  end
end
