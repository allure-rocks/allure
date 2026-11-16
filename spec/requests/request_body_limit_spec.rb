# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Request body limits (docs/dev/IMPORT-SOURCES.md)" do
  let(:user) { create(:user) }

  it "refuses an oversized import before the controller runs" do
    sign_in_as(user)
    too_large = Workouts::ArchiveReader::MAX_SOURCE_BYTES + Allure::RequestBodyLimit::OVERHEAD_BYTES + 1

    expect do
      post workout_imports_path, params: { workout_import_batch: { sport_id: catalog_sport("cycling").id } },
                                 env: { "CONTENT_LENGTH" => too_large.to_s }
    end.not_to change(WorkoutImportBatch, :count)

    expect(response).to have_http_status(:content_too_large)
  end

  it "refuses an oversized form anywhere else" do
    post session_path, params: { email_address: user.email_address },
                       env: { "CONTENT_LENGTH" => (Allure::RequestBodyLimit::DEFAULT_BYTES + 1).to_s }

    expect(response).to have_http_status(:content_too_large)
    expect(Session.count).to eq(0)
  end
end
