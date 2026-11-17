# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Records, segments, social and connection webhook events (docs/dev/API.md)" do
  let(:user) { create(:user) }
  let!(:endpoint) { user.webhook_endpoints.create!(url: "https://hooks.example.com/", events: [ "*" ]) }
  let(:actor) { Federation::ActorProvisioner.new(user:).call! }
  let(:other_actor) { Federation::ActorProvisioner.new(user: create(:user, display_name: "Paul")).call! }
  let(:workout) { create(:workout, user:) }
  let(:openapi) { JSONSchemer.openapi(YAML.safe_load_file(Rails.root.join("docs/openapi/v1.yaml"))) }

  def events(type) = WebhookEvent.where(user:, event_type: type)

  def expect_valid(event)
    schema = openapi.ref("#/webhooks/#{event.event_type}/post/requestBody/content/application~1json/schema")
    expect(schema.validate(JSON.parse(event.body)).map { it["error"] }).to be_empty
  end

  def notify(kind, subject:, actor: other_actor, payload: {})
    Notifications::Create.new(user:, kind:, actor:, subject:, payload:).call!
  end

  it "mirrors the notifications, whatever the in-app switches say" do
    user.update!(notify_follow_requests: false, notify_reactions: false)
    following = create(:following, follower_actor: other_actor, followed_actor: actor)
    reaction = create(:reaction, actor: other_actor, workout:, kind: "beer")
    comment = create(:comment, workout:, actor: other_actor)

    notify("follow_request", subject: following)
    notify("reaction", subject: reaction)
    notify("comment", subject: comment)

    expect(Notification.where(user:).pluck(:kind)).to eq([ "comment" ])
    expect(events("follow.requested").sole.payload.dig("account", "display_name")).to eq("Paul")
    expect(events("reaction.created").sole.payload).to include("workout_id" => workout.to_param, "type" => "beer")
    expect(events("comment.created").sole.payload).to include("comment_id" => comment.to_param, "reply_to_id" => nil)
    expect(events("comment.created").sole.payload.to_s).not_to include(comment.body)
    WebhookEvent.find_each { expect_valid(it) }
  end

  it "announces participations and connection events" do
    participation = create(:workout_participation, workout:, participant_actor: other_actor)
    connection = ImportConnection.for(user, "garmin_connect")
    connection.save!

    notify("participation_confirmed", subject: participation)
    notify("import_connection_expired", subject: connection, actor: nil, payload: { "provider" => "garmin_connect" })

    expect(events("import_connection.expired").sole.payload).to eq("provider" => "garmin_connect")
    expect(events("participation.confirmed").sole.payload).to include(
      "participation_id" => Allure::ShortId.encode(participation.uuid), "kind" => "credit"
    )
    WebhookEvent.find_each { expect_valid(it) }
  end

  it "announces a record when its holder changes, once" do
    workout.update!(distance: 42_000)
    Record.where(user:).delete_all
    WebhookEvent.delete_all

    2.times { Records::RecomputeService.new(user:, sport: workout.sport).call }

    record_event = events("record.achieved").find { it.payload["record_type"] == "FD" }
    expect(record_event.payload).to include("workout_id" => workout.to_param, "value" => 42_000)
    expect(events("record.achieved").where("payload ->> 'record_type' = 'FD'").count).to eq(1)
    expect_valid(record_event)
  end

  it "announces segment efforts of recent workouts only" do
    effort = create(:segment_effort, workout:, user:, sport: workout.sport)
    old = create(:workout, user:, created_at: 30.days.ago)
    old_effort = create(:segment_effort, workout: old, user:, sport: old.sport)

    Webhooks::Events.segment_efforts_created(workout, [ effort ])
    Webhooks::Events.segment_efforts_created(old, [ old_effort ])

    event = events("segment_effort.created").sole
    expect(event.payload).to include("segment_effort_id" => effort.to_param, "segment_id" => effort.segment.to_param)
    expect_valid(event)
  end

  it "tells the owner when the system disables a webhook, and again after a re-enable" do
    endpoint.disable!("gone")
    notice = Notification.where(user:, kind: "webhook_disabled").sole
    expect(notice.payload).to include("reason" => "gone", "host" => "hooks.example.com")

    Webhooks::Management.save(endpoint, active: true, fields: %i[active])
    expect(Notification.where(user:, kind: "webhook_disabled")).to be_empty

    endpoint.disable!("failing")
    expect(Notification.where(user:, kind: "webhook_disabled").sole.payload["reason"]).to eq("failing")
  end

  it "keeps the notice off when the account switched it off" do
    user.update!(notify_webhooks: false)

    endpoint.disable!("gone")

    expect(Notification.where(user:, kind: "webhook_disabled")).to be_empty
  end
end
