# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportConnections::Withings::LinkJob do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:connection) { ImportConnection.for(user, "withings") }
  let(:session) { instance_double(Allure::Withings::Session) }
  let(:signed_in) { Allure::Withings::Session::SignedIn.new(session_id: "S1", account_id: 42, body: {}) }

  around { |example| with_remote_import_enabled("withings") { example.run } }

  before do
    allow(described_class).to receive(:perform_later)
    allow(Workouts::RemoteImportBatchJob).to receive(:perform_later)
    stub_request(:post, "https://scalews.withings.net/cgi-bin/v2/activity")
      .to_return(body: JSON.generate({ "status" => 0, "body" => { "series" => [] } }))
  end

  def start!
    ImportConnections::Linking.new(connection).start!(email: "rider@example.test", password: "secret-pass")
  end

  def run = described_class.perform_now(connection.reload, session:)

  def signs_in
    allow(session).to receive(:sign_in).and_return(signed_in)
    allow(session).to receive(:users).with(signed_in).and_return([ { "id" => 7 } ])
  end

  it "carries only the connection in the job arguments, never the password" do
    start!

    expect(described_class).to have_received(:perform_later).with(connection)
  end

  it "links for a day and resumes the interrupted batches without starting a retrieval" do
    start!
    interrupted = create(:workout_import_batch, user:, source: "withings", status: "queued",
                                                trigger: "scheduled", import_connection: connection.reload)
    signs_in

    expect { run }.not_to change(WorkoutImportBatch, :count)

    expect(connection.reload).to have_attributes(
      status: "linked", external_account_id: "7", external_account_name: "rider@example.test",
      token_expires_at: be_within(1.minute).of(24.hours.from_now)
    )
    expect(connection.credentials).to eq("sessionid" => "S1", "userid" => 7)
    expect(Workouts::RemoteImportBatchJob).to have_received(:perform_later).with(interrupted).once
  end

  it "keeps the account linked when a step after the sign-in fails" do
    start!
    signs_in
    allow(Notifications::Withdraw).to receive(:new).and_raise(StandardError, "boom")
    allow(Rails.error).to receive(:report)

    run

    expect(connection.reload).to have_attributes(status: "linked")
    expect(connection.credentials).to eq("sessionid" => "S1", "userid" => 7)
    expect(Rails.error).to have_received(:report)
  end

  it "resumes nothing when the verification finds the session already ended" do
    start!
    create(:workout_import_batch, user:, source: "withings", status: "queued",
                                  trigger: "scheduled", import_connection: connection.reload)
    signs_in
    stub_request(:post, "https://scalews.withings.net/cgi-bin/v2/activity")
      .to_return(body: JSON.generate({ "status" => 501, "error" => "Invalid Session" }))

    expect { run }.not_to change(Notification, :count)

    expect(connection.reload).to have_attributes(status: "expired")
    expect(connection.last_sync_error).to eq(I18n.t("settings.connections.withings.errors.session_ended"))
    expect(Workouts::RemoteImportBatchJob).not_to have_received(:perform_later)
  end

  it "wipes the password on a refused sign-in and returns the row to its previous state" do
    start!
    allow(session).to receive(:sign_in).and_raise(Allure::Withings::Error::InvalidCredentials, "refused")

    run

    expect(connection.reload).to have_attributes(status: "unlinked")
    expect(connection.credentials).to eq({})
    expect(connection.last_sync_error).to eq(I18n.t("settings.connections.withings.errors.invalid_credentials"))
  end

  it "wipes the password and records an unavailable account" do
    start!
    allow(session).to receive(:sign_in).and_raise(Allure::Withings::Error::Unavailable, "no answer")

    run

    expect(connection.reload).to have_attributes(status: "unlinked")
    expect(connection.credentials).to eq({})
    expect(connection.last_sync_error).to eq(I18n.t("settings.connections.withings.errors.unavailable"))
  end
end
