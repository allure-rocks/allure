# frozen_string_literal: true

require "rails_helper"

# Bulk activity operations (PLAN_BULK_ACTIONS.md, DESIGN.md §10.19): the
# desktop table's selection, the synchronous quick actions, and the draft
# review that feeds the durable job. The selection UI is web-desktop only and
# never rendered in the iOS companion.
RSpec.describe "Workout bulk operations" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def desktop_headers
    { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                        "(KHTML, like Gecko) Chrome/126.0 Safari/537.36" }
  end

  def companion_headers
    { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " \
                        "(KHTML, like Gecko) Mobile/15E148 Allure iOS/0.2.0 Hotwire Native iOS; " \
                        "bridge-components: []" }
  end

  before { sign_in_as(user) }

  describe "the table's selection UI" do
    it "renders the selection column and the bulk bar in the table view" do
      workout = create(:workout, user:, sport:, title: "Selectable ride")

      get workouts_path(view: "table"), headers: desktop_headers

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("form#workout-bulk-form")).to be_present
      checkbox = page.at_css("input[name='workout_ids[]'][value='#{workout.to_param}']")
      expect(checkbox).to be_present
      expect(checkbox["form"]).to eq("workout-bulk-form")
      expect(page.at_css("input[data-bulk-selection-target='all']")).to be_present
      expect(page.at_css("button[name='operation'][value='sport_change']")).to be_present
      expect(page.at_css("button[name='operation'][value='delete']")).to be_present
    end

    it "does not render the bulk markup in the card view" do
      create(:workout, user:, sport:)

      get workouts_path, headers: desktop_headers

      expect(response.body).not_to include("workout-bulk-form", "workout_ids[]")
    end

    it "never renders the bulk markup in the iOS companion, even in the table view" do
      create(:workout, user:, sport:)

      get workouts_path(view: "table"), headers: companion_headers

      expect(response.body).not_to include("workout-bulk-form", "workout_ids[]", "bulk-selection")
      expect(response.body).to include("<table")
    end

    it "offers the filtered scope only when the page is not the whole result" do
      create_list(:workout, 21, user:, sport:)

      get workouts_path(view: "table"), headers: desktop_headers

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[name='scope'][value='filter']")).to be_present
      expect(page.text).to include(I18n.t("workouts.bulk.bar.select_filtered", count: 21))
    end

    it "replaces the scope switch with the cap hint above the maximum" do
      create_list(:workout, 21, user:, sport:)
      stub_const("Workouts::BulkSelection::MAX_WORKOUTS", 10)

      get workouts_path(view: "table"), headers: desktop_headers

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[name='scope']")).to be_nil
      expect(page.text).to include(I18n.t("workouts.bulk.bar.limit_hint", max: 10))
    end
  end

  describe "quick actions" do
    it "marks the selected workouts as commute and ignores foreign and malformed ids" do
      mine = create(:workout, user:, sport:, commute: false)
      foreign = create(:workout, user: create(:user), sport:)

      patch apply_workout_bulk_operations_path,
            params: { quick_operation: "commute_on",
                      workout_ids: [ mine.to_param, foreign.to_param, "not-a-short-id" ] }

      expect(mine.reload.commute).to be(true)
      expect(foreign.reload.commute).to be(false)
      expect(flash[:notice]).to eq(I18n.t("workouts.bulk.notices.commute_on", count: 1))
    end

    it "clears the commute flag" do
      workout = create(:workout, user:, sport:, commute: true)

      patch apply_workout_bulk_operations_path,
            params: { quick_operation: "commute_off", workout_ids: [ workout.to_param ] }

      expect(workout.reload.commute).to be(false)
      expect(flash[:notice]).to eq(I18n.t("workouts.bulk.notices.commute_off", count: 1))
    end

    it "says nothing changed when the flag already matches" do
      workout = create(:workout, user:, sport:, commute: true)

      patch apply_workout_bulk_operations_path,
            params: { quick_operation: "commute_on", workout_ids: [ workout.to_param ] }

      expect(flash[:notice]).to eq(I18n.t("workouts.bulk.notices.commute_on.none"))
    end

    it "attaches an active equipment and refreshes its totals once" do
      equipment = create(:equipment, user:, is_active: true)
      first = create(:workout, user:, sport:, distance: 1_000, moving_time: 600, pause_time: 0, duration: 600)
      second = create(:workout, user:, sport:, distance: 2_000, moving_time: 1_200, pause_time: 0, duration: 1_200)

      patch apply_workout_bulk_operations_path,
            params: { quick_operation: "equipment_add:#{equipment.id}",
                      workout_ids: [ first.to_param, second.to_param ] }

      expect(equipment.reload.workouts).to contain_exactly(first, second)
      expect(equipment.total_workouts).to eq(2)
      expect(equipment.total_distance).to eq(3_000)
      expect(equipment.total_moving).to eq(1_800)
      expect(flash[:notice]).to eq(I18n.t("workouts.bulk.notices.equipment_add", count: 2))
    end

    it "detaches equipment from the selection" do
      equipment = create(:equipment, user:)
      workout = create(:workout, user:, sport:)
      workout.equipments << equipment

      patch apply_workout_bulk_operations_path,
            params: { quick_operation: "equipment_remove:#{equipment.id}", workout_ids: [ workout.to_param ] }

      expect(equipment.reload.workouts).to be_empty
      expect(equipment.total_workouts).to eq(0)
    end

    it "refuses another account's equipment without a hint" do
      equipment = create(:equipment, user: create(:user))
      workout = create(:workout, user:, sport:)

      patch apply_workout_bulk_operations_path,
            params: { quick_operation: "equipment_add:#{equipment.id}", workout_ids: [ workout.to_param ] }

      expect(equipment.reload.workouts).to be_empty
      expect(flash[:alert]).to eq(I18n.t("workouts.bulk.errors.invalid_action"))
    end

    it "replays the list filters for a scope selection" do
      running = catalog_sport("running")
      cycling = catalog_sport("cycling")
      kept = create(:workout, user:, sport: running, commute: false)
      create(:workout, user:, sport: cycling, commute: false)

      patch apply_workout_bulk_operations_path,
            params: { scope: "filter", quick_operation: "commute_on", sports: [ running.id.to_s ] }

      expect(kept.reload.commute).to be(true)
      expect(Workout.where(user:, commute: true).count).to eq(1)
    end

    it "refuses a selection above the cap and writes nothing" do
      workouts = create_list(:workout, 3, user:, sport:, commute: false)
      stub_const("Workouts::BulkSelection::MAX_WORKOUTS", 2)

      patch apply_workout_bulk_operations_path,
            params: { quick_operation: "commute_on", workout_ids: workouts.map(&:to_param) }

      expect(flash[:alert]).to eq(I18n.t("workouts.bulk.errors.too_many", max: 2))
      expect(workouts.map { |workout| workout.reload.commute }).to all(be(false))
    end

    it "asks for an action and a selection" do
      workout = create(:workout, user:, sport:)

      patch apply_workout_bulk_operations_path, params: { workout_ids: [ workout.to_param ] }
      expect(flash[:alert]).to eq(I18n.t("workouts.bulk.errors.missing_action"))

      patch apply_workout_bulk_operations_path, params: { quick_operation: "commute_on" }
      expect(flash[:alert]).to eq(I18n.t("workouts.bulk.errors.no_selection"))
    end
  end

  describe "the review draft" do
    it "freezes the submitted order into a draft and shows the exact summary" do
      first = create(:workout, user:, sport:, title: "First", started_at: Time.zone.local(2026, 5, 3, 8))
      second = create(:workout, user:, sport:, title: "Second", started_at: Time.zone.local(2026, 9, 28, 8))
      second.original_file.attach(io: StringIO.new("bytes"), filename: "ride.fit",
                                  content_type: "application/octet-stream")

      post review_workout_bulk_operations_path,
           params: { operation: "sport_change", workout_ids: [ second.to_param, first.to_param ],
                     return_to: workouts_path(view: "table") }

      operation = user.workout_bulk_operations.order(:id).last
      expect(response).to redirect_to(workout_bulk_operation_path(operation))
      expect(operation.status).to eq("draft")
      expect(operation.operation).to eq("sport_change")
      expect(operation.items.in_order.map(&:workout_id)).to eq([ second.id, first.id ])
      expect(operation.return_to).to eq(workouts_path(view: "table"))

      follow_redirect!
      expect(response.body).to include(I18n.t("workouts.bulk.review.selection", count: 2))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.bulk.review.missing_original", count: 1)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.bulk.review.sport_hint", count: 2)))
      expect(response.body).to include(%(name="sport_id"))
    end

    it "cancels the account's previous draft" do
      workout = create(:workout, user:, sport:)
      previous = WorkoutBulkOperation.start_draft!(user:, operation: "delete", workout_ids: [ workout.id ])

      post review_workout_bulk_operations_path,
           params: { operation: "delete", workout_ids: [ workout.to_param ] }

      expect(previous.reload.status).to eq("cancelled")
      expect(user.workout_bulk_operations.drafts.count).to eq(1)
    end

    it "keeps another account's workouts out of the draft" do
      mine = create(:workout, user:, sport:)
      foreign = create(:workout, user: create(:user), sport:)

      post review_workout_bulk_operations_path,
           params: { operation: "delete", workout_ids: [ mine.to_param, foreign.to_param ] }

      operation = user.workout_bulk_operations.order(:id).last
      expect(operation.items.map(&:workout_id)).to eq([ mine.id ])
    end

    it "refuses an unknown operation and an empty selection" do
      post review_workout_bulk_operations_path, params: { operation: "nonsense" }
      expect(flash[:alert]).to eq(I18n.t("workouts.bulk.errors.invalid_action"))

      post review_workout_bulk_operations_path, params: { operation: "delete" }
      expect(flash[:alert]).to eq(I18n.t("workouts.bulk.errors.no_selection"))
      expect(user.workout_bulk_operations.count).to eq(0)
    end
  end

  describe "confirming a draft" do
    it "queues a deletion and enqueues the job" do
      workout = create(:workout, user:, sport:)
      operation = WorkoutBulkOperation.start_draft!(user:, operation: "delete", workout_ids: [ workout.id ])
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      patch workout_bulk_operation_path(operation)

      expect(operation.reload.status).to eq("queued")
      expect(Workouts::BulkOperationJob).to have_been_enqueued.with(operation.id, operation.user_id)
      expect(response).to redirect_to(workout_bulk_operation_path(operation))
    end

    it "requires a sport for a sport change and keeps the draft" do
      workout = create(:workout, user:, sport:)
      operation = WorkoutBulkOperation.start_draft!(user:, operation: "sport_change", workout_ids: [ workout.id ])

      patch workout_bulk_operation_path(operation)

      expect(response).to have_http_status(:unprocessable_content)
      expect(operation.reload.status).to eq("draft")
      expect(response.body).to include(I18n.t("workouts.import.errors.missing_sport"))
    end

    it "refuses a double confirm" do
      workout = create(:workout, user:, sport:)
      operation = WorkoutBulkOperation.start_draft!(user:, operation: "delete", workout_ids: [ workout.id ])
      patch workout_bulk_operation_path(operation)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      patch workout_bulk_operation_path(operation)

      expect(flash[:alert]).to eq(I18n.t("workouts.bulk.confirm.not_draft"))
      expect(Workouts::BulkOperationJob).not_to have_been_enqueued
    end

    it "cancels a draft outright" do
      workout = create(:workout, user:, sport:)
      operation = WorkoutBulkOperation.start_draft!(user:, operation: "delete", workout_ids: [ workout.id ])

      post cancel_workout_bulk_operation_path(operation)

      expect(operation.reload.status).to eq("cancelled")
      expect(operation.items.map(&:status)).to eq([ "cancelled" ])
    end

    it "answers 404 for another account's operation" do
      foreign = create(:workout_bulk_operation, user: create(:user))

      get workout_bulk_operation_path(foreign)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the progress page" do
    it "renders the counters, the items and the terminal summary" do
      workout = create(:workout, user:, sport:)
      operation = WorkoutBulkOperation.start_draft!(user:, operation: "delete", workout_ids: [ workout.id ])
      operation.confirm!
      operation.complete!
      operation.items.first.mark_modified!

      get workout_bulk_operation_path(operation)

      expect(response.body).to include(I18n.t("workouts.bulk.progress.summary",
                                              modified_label: I18n.t("workouts.bulk.counters.delete.modified"),
                                              modified: 1, skipped: 0, failed: 0, cancelled: 0))
      expect(response.body).to include(I18n.t("workouts.bulk.progress.back"))

      get status_workout_bulk_operation_path(operation)
      expect(response.body).to include(I18n.t("workouts.bulk.item_statuses.modified"))
    end
  end
end
