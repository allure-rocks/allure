# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout delivery summary" do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner, title: "Shareable ride") }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  # Server-rendered copy is HTML-escaped; compare against the escaped form.
  def escaped(key, **options)
    CGI.escapeHTML(I18n.t(key, **options))
  end

  def publish!
    sign_in_as(owner)
    post publish_workout_path(workout), params: { publishing_profile_id: profile.id, publish_delay: 0 }
    publication = workout.reload.active_publications.first
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer).to receive(:call)
      .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "no browser")
    Workouts::RenderPublicationRouteImageJob.perform_now(publication)
    publication.reload
  end

  def add_delivery(event, status, *actor_uris, inbox: nil)
    delivery = create(
      :federation_delivery,
      outbox_event: event,
      status:,
      inbox_url: inbox || "https://remote.example/inbox-#{SecureRandom.hex(4)}"
    )
    actor_uris.each { |uri| create(:federation_delivery_recipient, delivery:, actor_uri: uri) }
    delivery
  end

  def delivery_alert
    Nokogiri::HTML(response.body).at_css("#section-sharing .allure-publication-row .alert-warning")
  end

  it "lists the active publication by its profile and date, never as a second copy of the workout" do
    publish!
    workout.update!(title: "Edited after publishing")

    get workout_path(workout)

    expect(response).to have_http_status(:ok)
    row = Nokogiri::HTML(response.body).at_css("#section-sharing .allure-publication-row")
    expect(row.at_css('[data-audience-state="public"]')).to be_present
    expect(row.text).to include(I18n.t("workouts.snapshot.profile", name: profile.name))
    expect(row.at_css("a[href='#{workout_path(workout, as: :publication, audience: "public")}']")).to be_present
    # The frozen title lives on the reader's view, not in a projected card.
    expect(row.text).not_to include("Shareable ride")
    expect(response.body).to include(escaped("workouts.publication.replace"))
    expect(response.body).to include(escaped("workouts.publication.replace_hint"))
  end

  it "hides the publication list and distribution from non-owners" do
    publish!
    other = create(:user)
    sign_in_as(other)

    get workout_path(workout)

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("#section-sharing")).to be_nil
    expect(response.body).not_to include(I18n.t("workouts.delivery.refresh"))
  end

  it "stays silent while distribution has no problem" do
    publication = publish!
    allow(Allure::Federation::Config).to receive(:enabled?).and_return(false)
    sign_in_as(owner)
    get workout_path(workout)
    expect(delivery_alert).to be_nil

    allow(Allure::Federation::Config).to receive(:enabled?).and_call_original
    get workout_path(workout)
    expect(delivery_alert).to be_nil

    create_event = FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
    add_delivery(create_event, "delivered", "https://remote.example/users/one")
    create_event.update!(status: "complete")
    get workout_path(workout)
    expect(delivery_alert).to be_nil
  end

  it "reports partial delivery with failed counts" do
    publication = publish!
    create_event = FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
    add_delivery(create_event, "delivered", "https://remote.example/users/one")
    add_delivery(create_event, "failed", "https://remote.example/users/two")
    create_event.update!(status: "failed", last_error: "one or more deliveries failed")
    sign_in_as(owner)

    get workout_path(workout)

    expect(delivery_alert.text).to include(I18n.t("workouts.delivery.partial"))
    expect(delivery_alert.text).to include(I18n.t("workouts.delivery.failed_deliveries", count: 1))
    expect(delivery_alert.at_css("form[action='#{delivery_refresh_workout_path(workout)}']")).to be_present
  end

  it "reports unavailable after exhausted retries" do
    publication = publish!
    create_event = FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
    add_delivery(create_event, "failed", "https://remote.example/users/one")
    create_event.update!(status: "failed", last_error: "one or more deliveries failed")
    sign_in_as(owner)

    get workout_path(workout)

    expect(delivery_alert.text).to include(I18n.t("workouts.delivery.unavailable"))
  end

  it "refreshes delivery state through the explicit action" do
    publication = publish!
    create_event = FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
    retrying = add_delivery(create_event, "retrying", "https://remote.example/users/one")
    retrying.update_columns(next_attempt_at: 1.minute.ago)
    sign_in_as(owner)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    post delivery_refresh_workout_path(workout)

    expect(response).to redirect_to(workout_path(workout))
    expect(flash[:notice]).to eq(I18n.t("workouts.delivery.refresh_success"))
    expect(Federation::DeliverJob).to have_been_enqueued
  end

  it "rejects delivery refresh for non-owners and unpublished workouts" do
    other = create(:user)
    sign_in_as(other)

    post delivery_refresh_workout_path(workout)
    expect(response).to have_http_status(:not_found)

    sign_in_as(owner)
    post delivery_refresh_workout_path(workout)
    expect(response).to have_http_status(:not_found)
  end

  it "asks for replace confirmation with the irrevocability warning" do
    publish!
    sign_in_as(owner)

    get workout_path(workout)

    expect(response.body).to include(escaped("workouts.publication.replace_confirm.title"))
    expect(response.body).to include(escaped("workouts.publication.replace_confirm.body"))
  end
end
