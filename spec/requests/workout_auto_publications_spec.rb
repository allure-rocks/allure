# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout automatic publications" do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let(:workout) { create(:workout, user: owner, title: "Morning ride") }
  let!(:track_segment) { create(:track_segment, workout:) }
  let!(:profile) do
    create(:publishing_profile, :without_endpoint_masks, user: owner, auto_publish: true, auto_publish_acknowledged: true)
  end

  def waiting_row
    workout.auto_publications.create!(publishing_profile: profile, audience: "public", deadline_at: 6.hours.from_now)
  end

  it "shows a waiting publication to its owner and lets them decline it" do
    row = waiting_row
    sign_in_as(owner)

    get workout_path(workout)
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("auto_publications.status.waiting", audience: "Public")))
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("auto_publications.cancel.button")))

    delete auto_publication_workout_path(workout), params: { audience: "public" }

    expect(response).to redirect_to(workout_path(workout, anchor: "section-sharing"))
    expect(row.reload).to have_attributes(status: "skipped", reason: "cancelled_by_owner")
    Workouts::AutoPublisher.new(workout: workout.reload).call
    expect(workout.workout_publications).to be_empty
  end

  it "marks a publication an automatic profile made and explains a refusal" do
    publication = Workouts::Publisher.new(user: owner, workout:, profile:).call!
    waiting_row.settle!("published", publication:)
    sign_in_as(owner)

    get workout_path(workout)
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("auto_publications.badge")))

    workout.auto_publications.delete_all
    Workouts::PublicationWithdrawal.new(user: owner, publication:).call!
    waiting_row.settle!("failed", reason: "enrichment_timeout")

    get workout_path(workout)
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("auto_publications.reasons.enrichment_timeout", hours: 6)))
  end

  it "does not let another account decline it" do
    row = waiting_row
    sign_in_as(other)

    delete auto_publication_workout_path(workout), params: { audience: "public" }

    expect(response).to have_http_status(:not_found)
    expect(row.reload).to be_waiting
  end
end
