# frozen_string_literal: true

require "rails_helper"

# Unsaved changes (DESIGN.md §14.3): the dialog belongs to the members' chrome,
# a form re-rendered with its validation summary is marked unsaved, and a form
# holding a transient choice opts out.
RSpec.describe "Unsaved changes" do
  let(:user) { create(:user) }

  it "renders the dialog on a settings page" do
    sign_in_as(user)

    get settings_profile_path

    expect(response).to have_http_status(:ok)
    page = response.parsed_body
    controller = page.at_css("[data-controller='unsaved-changes']")
    expect(controller).to be_present
    expect(page.at_css("#unsaved-changes-modal")).to be_present
    expect(page.at_css("#unsaved-changes-modal .modal-title").text)
      .to eq(I18n.t("unsaved_changes.leave.title"))
    expect(controller["data-unsaved-changes-messages-value"])
      .to include(I18n.t("unsaved_changes.leave.action"))
  end

  it "keeps the guard off the sign-in page" do
    get new_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("data-controller=\"unsaved-changes\"")
    expect(response.body).not_to include("data-controller='unsaved-changes'")
  end

  it "renders in the administration console" do
    operator = create(:user, :with_totp, username: "operator")
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    sign_in_as(operator)

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css("#unsaved-changes-modal")).to be_present
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  it "marks a form re-rendered with its validation summary as unsaved" do
    sign_in_as(user)
    equipment_type = create(:equipment_type)

    post equipments_path, params: { equipment: { label: "", equipment_type_id: equipment_type.id } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css("form [data-unsaved-changes='forced']")).to be_present
  end

  it "leaves the bulk selection out of the guard" do
    sign_in_as(user)
    create(:workout, user:, sport: catalog_sport("running"))

    get workouts_path(view: "table")

    expect(response).to have_http_status(:ok)
    form = response.parsed_body.at_css("form#workout-bulk-form")
    expect(form).to be_present
    expect(form["data-unsaved-changes"]).to eq("off")
  end
end
