# frozen_string_literal: true

require "rails_helper"

# The manual import source (docs/dev/MANUAL-ENTRY.md): a workout typed in from the
# import page, shown and edited by its owner, never published.
RSpec.describe "Manual entries" do
  let(:owner) { create(:user, time_zone: "Europe/Paris") }
  let(:running) { catalog_sport("running") }
  let(:form_params) do
    { sport_id: running.id, started_at: "2026-10-17T07:30", duration_hours: "0", duration_minutes: "45",
      duration_seconds: "30", distance: "8,5", ascent: "120", average_heart_rate: "145", max_heart_rate: "170",
      title: "Footing sans montre", equipment_ids: [ "" ] }
  end

  before { sign_in_as(owner) }

  describe "the import page" do
    it "offers the manual source with its own form outside the upload form" do
      get new_workout_import_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("workouts.batch_import.sources.manual.label"))
      expect(response.body).to include(%(action="#{manual_workouts_path}"))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.manual.form.intro")))
    end
  end

  describe "POST /workouts/manual" do
    it "creates the entry and opens its page" do
      expect { post manual_workouts_path, params: { manual_workout: form_params } }
        .to change { owner.workouts.manual_entries.count }.by(1)

      workout = owner.workouts.manual_entries.last
      expect(response).to redirect_to(workout_path(workout))
      expect(workout).to have_attributes(sport: running, duration: 2730, moving_time: 2730, distance: 8_500,
                                         ascent: 120, average_heart_rate: 145, max_heart_rate: 170,
                                         started_at: Time.utc(2026, 10, 17, 5, 30))
    end

    it "returns to the manual panel with what was typed and each refusal" do
      post manual_workouts_path, params: { manual_workout: form_params.merge(max_heart_rate: "120", distance: "8.5") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('data-import-source-initial-value="manual"')
      expect(response.body).to include("Footing sans montre")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("activerecord.errors.models.workout.below_average")))
      expect(owner.workouts).to be_empty
    end
  end

  describe "the entry's page" do
    let(:workout) do
      create(:workout, :manual, user: owner, sport: running, title: "Séance", average_heart_rate: 140, calories: 500)
    end

    it "shows the typed figures, the manual badge and the scope, with no map and no publication" do
      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("workouts.manual.badge"))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.manual.show.scope")))
      expect(response.body).to include(edit_workout_path(workout))
      expect(response.body).not_to include('id="section-map"')
      expect(response.body).not_to include(publish_workout_path(workout))
      expect(response.body).not_to include(workout_original_file_path(workout))
    end

    it "answers 404 to another account" do
      sign_in_as(create(:user))

      get workout_path(workout)

      expect(response).to have_http_status(:not_found)
    end

    it "edits every figure through the same form" do
      get edit_workout_path(workout)
      expect(response.body).to include(%(name="manual_workout[duration_hours]"))

      patch workout_path(workout), params: { manual_workout: form_params.merge(duration_hours: "1", moving_minutes: "50") }

      expect(response).to redirect_to(workout_path(workout))
      expect(workout.reload).to have_attributes(duration: 6330, moving_time: 3000, pause_time: 3330,
                                                title: "Footing sans montre")
    end

    it "refuses a publication: an entry has no route to share" do
      post publish_workout_path(workout)

      expect(workout.reload.active_publications).to be_empty
    end

    it "is listed, selectable in bulk, and never asks for a route image" do
      workout
      get workouts_path(view: "table")

      expect(response.body).to include(%(value="#{workout.to_param}"))
      expect(response.body).not_to include(workout_route_image_path(workout))
    end
  end
end
