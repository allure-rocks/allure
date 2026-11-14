# frozen_string_literal: true

require "rails_helper"

# The document's `webhooks` section is the contract of every event Allure
# sends (PLAN_API.md §11.2, §12): one entry per type, and each real envelope
# validates against it.
RSpec.describe "Webhook event schemas" do
  let(:document) { YAML.safe_load_file(Rails.root.join("docs/openapi/v1.yaml"), aliases: true) }
  let(:openapi) { JSONSchemer.openapi(document) }
  let(:user) { create(:user) }
  let!(:endpoint) { user.webhook_endpoints.create!(url: "https://hooks.example.com/", events: [ "*" ]) }

  def schema_for(type)
    openapi.ref("#/webhooks/#{type.gsub('/', '~1')}/post/requestBody/content/application~1json/schema")
  end

  def expect_valid(event)
    envelope = JSON.parse(event.body)
    errors = schema_for(event.event_type).validate(envelope).map { it["error"] }
    expect(errors).to be_empty, "#{event.event_type}: #{errors.join('; ')}"
  end

  it "documents exactly the events an endpoint can subscribe to, and ping" do
    expect(document.fetch("webhooks").keys).to match_array(WebhookEndpoint::EVENT_TYPES + [ "ping" ])
  end

  it "sends envelopes that match their schema" do
    workout = create(:workout, user:)
    create(:track_segment, workout:)
    Webhooks::Events.workout_created(workout)
    Webhooks::Events.workout_updated(workout, %w[title])
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    publication = Workouts::Publisher.new(user:, workout:, profile:).call!
    Workouts::PublicationDeletion.new(user:, workout:, publication:).call!
    Webhooks::Management.ping!(endpoint)
    Webhooks::Events.workout_deleted(user, workout.to_param)

    expect(WebhookEvent.pluck(:event_type)).to include("workout.created", "workout.updated", "publication.activated",
                                                       "publication.withdrawn", "ping", "workout.deleted")
    WebhookEvent.find_each { expect_valid(it) }
  end
end
