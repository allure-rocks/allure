# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Equipments" do
  let(:user) { create(:user) }
  let(:equipment_type) { create(:equipment_type) }

  def sign_in_as(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  it "requires authentication" do
    get equipments_path

    expect(response).to redirect_to(new_session_path)
  end

  it "lists only the current user's equipment" do
    own = create(:equipment, user:, label: "Road bike")
    create(:equipment, label: "Hidden bike")
    sign_in_as

    get equipments_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own.label)
    expect(response.body).not_to include("Hidden bike")
  end

  it "shows the empty state with no equipment" do
    sign_in_as

    get equipments_path

    expect(response.body).to include(I18n.t("equipments.index.empty_title"))
  end

  it "shows an owned item with totals and attached workouts, and 404s others" do
    equipment = create(:equipment, user:, equipment_type:, label: "Road bike")
    other = create(:equipment, label: "Hidden bike")
    sign_in_as

    get equipment_path(equipment)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Road bike", I18n.t("equipments.totals.distance"))

    get equipment_path(other)
    expect(response).to have_http_status(:not_found)
  end

  it "creates with valid attributes" do
    sign_in_as

    expect do
      post equipments_path, params: { equipment: { label: "Gravel bike", description: "For mixed surfaces",
        equipment_type_id: equipment_type.id, is_active: "1" } }
    end.to change(Equipment, :count).by(1)

    expect(response).to redirect_to(equipments_path)
    expect(Equipment.last).to have_attributes(label: "Gravel bike", user:, equipment_type:)
  end

  it "rejects invalid attributes with unprocessable content" do
    sign_in_as

    post equipments_path, params: { equipment: { label: "", equipment_type_id: equipment_type.id } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "updates owned items and 404s others" do
    equipment = create(:equipment, user:)
    other = create(:equipment)
    sign_in_as

    patch equipment_path(equipment), params: { equipment: { label: "Renamed" } }
    expect(response).to redirect_to(equipment_path(equipment))
    expect(equipment.reload.label).to eq("Renamed")

    patch equipment_path(other), params: { equipment: { label: "Stolen" } }
    expect(response).to have_http_status(:not_found)
  end

  it "destroys owned items without deleting workouts" do
    equipment = create(:equipment, user:)
    workout = create(:workout, user:)
    Equipments::Totals.sync(workout, [ equipment.id ])
    other = create(:equipment)
    sign_in_as

    expect { delete equipment_path(equipment) }.to change(Equipment, :count).by(-1)

    expect(response).to redirect_to(equipments_path)
    expect(Workout.exists?(workout.id)).to be(true)
    expect(workout.reload.equipment_ids).to be_empty

    expect { delete equipment_path(other) }.not_to change(Equipment, :count)
  end

  it "refreshes drifted totals" do
    equipment = create(:equipment, user:)
    workout = create(:workout, user:, distance: 1000, moving_time: 600, duration: 700, pause_time: 100)
    Equipments::Totals.sync(workout, [ equipment.id ])
    equipment.update_columns(total_distance: 1, total_workouts: 99)
    sign_in_as

    post refresh_equipment_path(equipment)

    expect(response).to redirect_to(equipment_path(equipment))
    expect(equipment.reload).to have_attributes(total_distance: 1000, total_workouts: 1)
  end

  it "404s refresh on another user's item" do
    other = create(:equipment)
    sign_in_as

    post refresh_equipment_path(other)

    expect(response).to have_http_status(:not_found)
  end
end
