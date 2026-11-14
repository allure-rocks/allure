# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout publishing" do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let(:workout) { create(:workout, user: owner, title: "Shareable ride", notes: "Private note") }
  let!(:track_segment) { create(:track_segment, workout:) }

  def one_day = PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
  def one_week = PublishingProfile::PUBLISH_DELAYS.fetch("1_week")

  def publish_params(profile, delay: nil)
    params = { publishing_profile_id: profile.id }
    params[:publish_delay] = delay if delay
    params
  end

  def scheduled_params(profile)
    publish_params(profile, delay: one_day)
  end

  def activate!(publication)
    Workouts::ScheduledPublicationActivation.new(publication:, force: true).call!
  end

  it "publishes an owner workout immediately by default with a selected profile" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { post publish_workout_path(workout), params: publish_params(profile) }
      .to change(WorkoutPublication, :count).by(1)

    expect(response).to redirect_to(workout_path(workout))
    publication = workout.reload.active_publications.first
    expect(publication.publishing_profile).to eq(profile)
    expect(publication).not_to be_scheduled
    expect(workout.scheduled_publications.first).to be_nil
    expect(FederationOutboxEvent.where(activity_type: "Create", object_uri: publication.object_uri)).to exist
    expect(Workouts::ActivateScheduledPublicationJob).to have_been_enqueued.with(publication)
    expect(flash[:notice]).to eq(I18n.t("workouts.publish.success", audience: I18n.t("workouts.publication.audience.public")))
  end

  it "schedules an owner workout when a delay preset is selected, with no federation trace" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { post publish_workout_path(workout), params: scheduled_params(profile) }
      .to change(WorkoutPublication, :count).by(1)

    expect(response).to redirect_to(workout_path(workout))
    publication = workout.reload.scheduled_publications.first
    expect(publication.publishing_profile).to eq(profile)
    expect(publication.scheduled_for).to be_within(1.second).of(1.day.from_now)
    expect(workout.active_publications.first).to be_nil
    expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
    expect(Workouts::ActivateScheduledPublicationJob).to have_been_enqueued.with(publication)
    expect(flash[:notice]).to include(I18n.l(publication.scheduled_for, format: :long))
  end

  it "accepts a per-publish delay override" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)

    post publish_workout_path(workout), params: publish_params(profile, delay: 2_592_000)

    expect(workout.reload.scheduled_publications.first.scheduled_for).to be_within(1.second).of(30.days.from_now)
  end

  it "rejects a delay outside the presets" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)

    expect {
      post publish_workout_path(workout), params: publish_params(profile, delay: 3_600)
    }.not_to change(WorkoutPublication, :count)

    expect(response).to redirect_to(workout_path(workout))
    expect(flash[:alert]).to eq(I18n.t("workouts.publish.errors.invalid_delay"))
  end

  it "does not let another user publish the source workout" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: other)
    sign_in_as(other)

    post publish_workout_path(workout), params: publish_params(profile)

    expect(response).to have_http_status(:not_found)
    expect(workout.reload.scheduled_publications.first).to be_nil
  end

  it "rejects a second publication while one is scheduled" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)
    post publish_workout_path(workout), params: scheduled_params(profile)

    expect {
      post publish_workout_path(workout), params: publish_params(profile)
    }.not_to change(WorkoutPublication, :count)

    expect(response).to redirect_to(workout_path(workout))
    expect(flash[:alert]).to eq(I18n.t("workouts.publish.errors.already_scheduled"))
  end

  it "lists the scheduled publication with its actions instead of the publish form" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)
    post publish_workout_path(workout), params: scheduled_params(profile)

    get workout_path(workout)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css("#section-sharing .allure-publication-list .allure-scheduled-publication")).to be_present
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.scheduled.notice")))
    expect(response.body).to include(I18n.l(workout.reload.scheduled_publications.first.scheduled_for, format: :long))
    expect(response.body).to include(activate_publication_workout_path(workout))
    expect(response.body).to include(reschedule_publication_workout_path(workout))
    expect(response.body).to include(scheduled_publication_workout_path(workout))
    # Publish now already means immediate; the reschedule select omits it.
    delay_values = response.parsed_body.css(".allure-scheduled-publication select[name='publish_delay'] option").map { |option| option["value"] }
    expect(delay_values).not_to include("0")
    # Nothing is projected and nothing is live yet: no withdraw-all, and the
    # add action only offers the audience the scheduled one leaves free.
    expect(response.parsed_body.at_css("#section-sharing").text).not_to include("Shareable ride")
    expect(response.body).not_to include(I18n.t("workouts.publication.delete_all"))
    expect(response.parsed_body.at_css("#section-sharing .allure-publication-list button[disabled]")).to be_nil
    followers = owner.publishing_profiles.find_by!(built_in_key: "followers")
    offered = response.parsed_body.css("select[name='publishing_profile_id'] option").map { it["value"] }
    expect(offered).to include(followers.id.to_s)
    expect(offered).not_to include(profile.id.to_s)
  end

  it "shows the delay selector with the profile default and an honest submit label" do
    profile = create(:publishing_profile, :custom, :without_endpoint_masks, user: owner, audience: "public")
    sign_in_as(owner)

    get workout_path(workout)

    expect(response.body).to include(I18n.t("workouts.publication.delay"))
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.publication.delay_hint")))
    selected = response.parsed_body.at_css("select[name='publish_delay'] option[selected]")
    expect(selected["value"]).to eq("0")
    expect(selected.text).to eq(I18n.t("publishing_profiles.delays.immediate"))
    submit = response.parsed_body.at_css("input[name='commit']")
    expect(submit["value"]).to eq(I18n.t("workouts.publication.publish"))

    profile.update!(publish_delay_seconds: one_week)
    get workout_path(workout)

    selected = response.parsed_body.at_css("select[name='publish_delay'] option[selected]")
    expect(selected["value"]).to eq(one_week.to_s)
    submit = response.parsed_body.at_css("input[name='commit']")
    expect(submit["value"]).to eq(I18n.t("workouts.publication.schedule"))
  end

  it "keeps a scheduled publication invisible until activation" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)
    post publish_workout_path(workout), params: scheduled_params(profile)
    publication = workout.reload.scheduled_publications.first

    get workout_publication_path(publication)
    expect(response).to have_http_status(:not_found)

    sign_in_as(other)
    get workout_path(workout)
    expect(response).to have_http_status(:not_found)
    get workout_track_path(workout)
    expect(response).to have_http_status(:not_found)
  end

  it "publishes now from the scheduled state" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)
    post publish_workout_path(workout), params: scheduled_params(profile)
    publication = workout.reload.scheduled_publications.first

    expect { post activate_publication_workout_path(workout) }
      .to change { publication.reload.status }.from("scheduled").to("active")

    expect(response).to redirect_to(workout_path(workout))
    expect(workout.reload.active_publications.first).to eq(publication)
    expect(FederationOutboxEvent.where(activity_type: "Create", object_uri: publication.object_uri)).to exist

    get workout_publication_path(publication)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("id" => publication.object_uri, "name" => "Shareable ride")
  end

  it "cancels a scheduled publication with no Delete activity" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)
    post publish_workout_path(workout), params: scheduled_params(profile)
    publication = workout.reload.scheduled_publications.first

    expect { delete scheduled_publication_workout_path(workout) }
      .to change { publication.reload.status }.from("scheduled").to("deleted")

    expect(response).to redirect_to(workout_path(workout))
    expect(workout.reload.scheduled_publications.first).to be_nil
    expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
  end

  it "reschedules a scheduled publication and refuses an invalid delay" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)
    post publish_workout_path(workout), params: scheduled_params(profile)
    publication = workout.reload.scheduled_publications.first

    # Bounds taken around the request, not after it: a slow run must not
    # move the expected moment.
    before_reschedule = Time.current
    patch reschedule_publication_workout_path(workout), params: { publish_delay: one_week }
    rescheduled_for = publication.reload.scheduled_for
    expect(rescheduled_for).to be_between(before_reschedule + 1.week - 1.second, Time.current + 1.week)

    patch reschedule_publication_workout_path(workout), params: { publish_delay: 10 }
    expect(response).to redirect_to(workout_path(workout))
    expect(flash[:alert]).to eq(I18n.t("workouts.publish.errors.invalid_delay"))
    expect(publication.reload.scheduled_for).to eq(rescheduled_for)
  end

  it "withdraws, republishes with a new identity, and schedules the replacement" do
    first_profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    second_profile = create(:publishing_profile, :custom, :without_endpoint_masks, user: owner, audience: "public")
    sign_in_as(owner)
    post publish_workout_path(workout), params: publish_params(first_profile)
    first = workout.reload.active_publications.first
    first_create = FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: first.object_uri)

    delete publication_workout_path(workout)
    expect(response).to redirect_to(workout_path(workout))
    expect(first.reload).to be_deleted

    expect {
      post republish_workout_path(workout), params: scheduled_params(second_profile)
    }.to change(WorkoutPublication, :count).by(1)

    expect(response).to redirect_to(workout_path(workout))
    second = workout.reload.scheduled_publications.first
    expect(second).to be_present
    expect(second.uuid).not_to eq(first.uuid)
    expect(second.object_uri).not_to eq(first.object_uri)
    expect(FederationOutboxEvent.where(activity_type: "Delete", object_uri: first.object_uri)).to exist
    expect(FederationOutboxEvent.where(activity_type: "Create", object_uri: second.object_uri)).to be_empty
    expect(FederationOutboxEvent.where(activity_type: "Update")).to be_empty
    expect(first_create.reload.payload.dig("object", "id")).to eq(first.object_uri)
    expect(workout.reload).to be_persisted
  end

  it "schedules the built-in followers profile through the controller while restricted federation is off" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
    profile = create(:publishing_profile, :followers, :without_endpoint_masks, user: owner)
    sign_in_as(owner)

    expect { post publish_workout_path(workout), params: scheduled_params(profile) }
      .to change(WorkoutPublication, :count).by(1)

    expect(response).to redirect_to(workout_path(workout))
    expect(workout.reload.scheduled_publications.first.audience).to eq("followers")
  end

  it "keeps non-owner pages locked until the scheduled publication activates" do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    sign_in_as(owner)
    post publish_workout_path(workout), params: scheduled_params(profile)
    publication = workout.reload.scheduled_publications.first

    activation = Workouts::ScheduledPublicationActivation.new(publication:, force: true)
    sign_in_as(other)

    get workout_path(workout)
    expect(response).to have_http_status(:not_found)

    activation.call!

    get workout_path(workout)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Shareable ride")
    expect(response.body).not_to include("Private note")

    get workout_track_path(workout)
    expect(response).to have_http_status(:ok)

    workout.original_file.attach(io: StringIO.new("private gpx"), filename: "private.gpx", content_type: "application/gpx+xml")
    get workout_original_file_path(workout)
    expect(response).to have_http_status(:not_found)
  end

  it "shows endpoint-mask readiness warnings before publishing" do
    create(:track_segment, workout:)
    profile = create(:publishing_profile, user: owner)
    sign_in_as(owner)

    get workout_path(workout)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Le départ est configuré pour être masqué")
    expect(response.body).to include("data-publication-preview-readiness-value")
    expect(profile).to be_persisted
  end

  it "enables the followers profile in the selector while restricted federation is off" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
    create(:track_segment, workout:)
    create(:publishing_profile, user: owner)
    sign_in_as(owner)

    get workout_path(workout)

    followers = owner.publishing_profiles.find_by!(built_in_key: "followers")
    option = response.parsed_body.at_css("option[value='#{followers.id}']")
    expect(option["disabled"]).to be_nil
  end
end
