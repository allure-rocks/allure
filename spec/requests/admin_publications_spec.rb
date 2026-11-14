# frozen_string_literal: true

require "rails_helper"

# Publication oversight and takedown (PLAN_ADMIN.md §4.4). Takedown walks the
# immutable withdrawal lifecycle with an explicit operator authorization; the
# owner-only path must stay intact.
RSpec.describe "Admin publications" do
  let(:operator) { create(:user, :with_totp, username: "operator") }
  let(:member) { create(:user) }
  let(:workout) { create(:workout, user: member, title: "Ride to the lake") }
  let(:segment) { create(:segment, user: member, name: "Col du Test") }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    example.run
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  describe "authorization" do
    it "redirects an anonymous visitor" do
      get admin_publications_path

      expect(response).to redirect_to(new_session_path)
    end

    it "answers 404 to a member" do
      sign_in_as(member)

      get admin_publications_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "index" do
    before { sign_in_as(operator) }

    it "lists workout publications with owner, audience and state" do
      create(:workout_publication, workout:)

      get admin_publications_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ride to the lake")
      expect(response.body).to include("@#{member.username}")
      expect(response.body).to include(I18n.t("workouts.publication.audience.public"))
      expect(response.body).to include(I18n.t("admin.publications.tabs.workouts"))
    end

    it "lists course publications on their own tab" do
      create(:segment_publication, segment:)
      create(:workout_publication, workout:)

      get admin_publications_path(kind: "courses")

      expect(response.body).to include("Col du Test")
      expect(response.body).not_to include("Ride to the lake")
    end

    it "lists scheduled publications with their planned moment" do
      publication = create(:workout_publication, :scheduled, workout:)

      get admin_publications_path(status: "scheduled")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ride to the lake")
      expect(response.body).to include(I18n.t("admin.publications.statuses.scheduled"))
      expect(response.body).to include(
        I18n.t("admin.publications.scheduled_for", time: I18n.l(publication.scheduled_for, format: :long))
      )
    end

    it "filters by status and audience" do
      create(:workout_publication, workout:, status: "deleted", deleted_at: Time.current)
      create(:workout_publication, :with_followers, workout: create(:workout, user: member, title: "Followers only"))

      get admin_publications_path(status: "deleted")
      expect(response.body).to include("Ride to the lake")
      expect(response.body).not_to include("Followers only")

      get admin_publications_path(audience: "followers")
      expect(response.body).to include("Followers only")
      expect(response.body).not_to include("Ride to the lake")
    end
  end

  describe "takedown" do
    before { sign_in_as(operator) }

    it "withdraws a workout publication and audits the operator action" do
      publication = create(:workout_publication, workout:)

      post admin_workout_publication_withdraw_path(publication)

      expect(response).to redirect_to(admin_publications_path(kind: "workouts", status: "active"))
      expect(publication.reload).to be_deleted
      expect(AdminEvent.last).to have_attributes(action: "publication_withdrawn", user: operator)
      expect(AdminEvent.last.metadata).to include("kind" => "workout", "owner" => member.username)
    end

    it "cancels a scheduled publication locally and audits the operator action" do
      publication = create(:workout_publication, :scheduled, workout:)

      post admin_workout_publication_withdraw_path(publication)

      expect(response).to redirect_to(admin_publications_path(kind: "workouts", status: "scheduled"))
      expect(publication.reload).to be_deleted
      expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
      expect(AdminEvent.last).to have_attributes(action: "publication_schedule_cancelled", user: operator)
      expect(AdminEvent.last.metadata).to include("kind" => "workout", "owner" => member.username)
    end

    it "withdraws a course publication" do
      publication = create(:segment_publication, segment:)

      post admin_course_publication_withdraw_path(publication)

      expect(response).to redirect_to(admin_publications_path(kind: "courses", status: "active"))
      expect(publication.reload).to be_deleted
      expect(AdminEvent.last.metadata).to include("kind" => "course")
    end

    it "performs nothing for a member" do
      publication = create(:workout_publication, workout:)
      sign_in_as(member)

      post admin_workout_publication_withdraw_path(publication)

      expect(response).to have_http_status(:not_found)
      expect(publication.reload).to be_active
      expect(AdminEvent.count).to eq(0)
    end
  end
end
