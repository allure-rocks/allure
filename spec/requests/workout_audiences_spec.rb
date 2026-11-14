# frozen_string_literal: true

require "rails_helper"

# The workout page with one publication per audience (PLAN_AUDIENCES.md):
# the owner's sharing card, the per-row actions, and what each reader is
# served.
RSpec.describe "Workout publications per audience" do
  let(:owner) { create(:user) }
  let!(:owner_actor) { Federation::ActorProvisioner.new(user: owner).call! }
  let(:follower) { create(:user) }
  let(:stranger) { create(:user) }
  let(:workout) { create(:workout, user: owner, title: "Sortie partagée") }
  let!(:track_segment) { create(:track_segment, workout:) }
  let!(:public_profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }
  let!(:followers_profile) { create(:publishing_profile, :followers, :without_endpoint_masks, user: owner) }

  before do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    create(:following, :accepted, follower_actor: Federation::ActorProvisioner.new(user: follower).call!,
                                  followed_actor: owner_actor)
  end

  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def sharing = response.parsed_body.at_css("#section-sharing")

  it "adds a followers publication beside the public one" do
    publish_workout!(user: owner, workout:, profile: public_profile)
    sign_in_as(owner)

    get workout_path(workout)
    add = sharing.at_css("button[data-bs-target='#workout-publish-form-add']")
    expect(add).to be_present
    expect(add["disabled"]).to be_nil
    options = sharing.css("#workout-publish-form-add select[name='publishing_profile_id'] option").map(&:text)
    expect(options).to eq([ followers_profile.name ])

    expect { post publish_workout_path(workout), params: { publishing_profile_id: followers_profile.id } }
      .to change { workout.reload.active_publications.count }.from(1).to(2)
  end

  it "carries the same badge, its label printed, on the workout page and the sharing row" do
    publish_workout!(user: owner, workout:, profile: followers_profile)
    sign_in_as(owner)

    get workout_path(workout)

    page = response.parsed_body
    header = page.at_css(".page-pretitle [data-audience-state='followers']")
    expect(header["class"]).to include("allure-badge-responsive", "bg-info-lt")
    expect(header.at_css(".allure-badge-responsive__label").text).to eq(I18n.t("workouts.publication.audience.followers"))
    expect(header["data-tooltip-media-value"]).to eq(BadgesHelper::ICON_ONLY_MEDIA)

    row = sharing.at_css(".allure-publication-row [data-audience-state='followers']")
    expect(row["class"]).to include("allure-badge-responsive")
  end

  it "lists one row per publication, each with its own actions" do
    public_publication = publish_workout!(user: owner, workout:, profile: public_profile)
    followers_publication = publish_workout!(user: owner, workout:, profile: followers_profile)
    sign_in_as(owner)

    get workout_path(workout)

    rows = sharing.css(".allure-publication-row")
    expect(rows.map { |row| row.at_css("[data-audience-state]")["data-audience-state"] }).to eq(%w[followers public])
    [ followers_publication, public_publication ].each_with_index do |publication, index|
      expect(rows[index].at_css("input[name='publication_id'][value='#{publication.to_param}']")).to be_present
      expect(rows[index].at_css("a[href='#{workout_path(workout, as: :publication, audience: publication.audience)}']")).to be_present
    end
    expect(sharing.at_css("button[data-bs-target='#workout-publish-form-add'][disabled]")).to be_nil
    expect(sharing.text).to include(I18n.t("workouts.publication.add"))
    expect(sharing.text).to include(I18n.t("workouts.publication.add_unavailable"))

    delete publication_workout_path(workout), params: { publication_id: followers_publication.to_param }

    expect(followers_publication.reload).to be_deleted
    expect(public_publication.reload).to be_active
  end

  it "withdraws every publication from the card header" do
    publications = [ publish_workout!(user: owner, workout:, profile: public_profile),
                     publish_workout!(user: owner, workout:, profile: followers_profile) ]
    sign_in_as(owner)

    delete publication_workout_path(workout)

    expect(publications.map { |publication| publication.reload.status }).to all(eq("deleted"))
  end

  it "serves each reader one version and lets the owner preview each" do
    publish_workout!(user: owner, workout:, profile: public_profile)
    publish_workout!(user: owner, workout:, profile: followers_profile)

    sign_in_as(follower)
    get workout_path(workout)
    expect(response.parsed_body.at_css(".page-pretitle [data-audience-state]")["data-audience-state"]).to eq("followers")

    sign_in_as(stranger)
    get workout_path(workout)
    expect(response.parsed_body.at_css(".page-pretitle [data-audience-state]")["data-audience-state"]).to eq("public")

    sign_in_as(owner)
    get workout_path(workout, as: :publication, audience: "public")
    expect(response.parsed_body.at_css(".page-pretitle [data-audience-state]")["data-audience-state"]).to eq("public")
    expect(response.body).to include(CGI.escapeHTML(workout_track_path(workout, as: :publication, audience: "public")))
  end

  it "hides a followers-only workout from a stranger" do
    publish_workout!(user: owner, workout:, profile: followers_profile)
    sign_in_as(stranger)

    get workout_path(workout)

    expect(response).to have_http_status(:not_found)
  end
end
