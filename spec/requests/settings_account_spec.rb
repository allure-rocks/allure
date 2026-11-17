# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings: account (docs/dev/ACCOUNT.md)", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :with_totp) }

  before { sign_in_as(user) }

  def ready_export(owner = user, expires_at: 6.days.from_now)
    owner.account_exports.create!(status: "ready", completed_at: 1.hour.ago, expires_at:, byte_size: 7).tap do
      it.archive.attach(io: StringIO.new("PK-data"), filename: it.filename, content_type: "application/zip")
    end
  end

  it "shows the export and deletion cards, linked from the settings navigation" do
    get settings_account_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("settings.account.export.title"), I18n.t("settings.account.deletion.title"))
    expect(response.body).to include(%(href="#{settings_account_path}"))
  end

  describe "the export (§3)" do
    it "asks for a recent proof of identity first" do
      Session.last.update!(reauthenticated_at: 1.hour.ago)

      post settings_account_exports_path

      expect(response).to redirect_to(new_reauthentication_path)
      expect(user.account_exports).to be_empty
    end

    it "queues one export, then refuses another within the cooldown" do
      post settings_account_exports_path

      export = user.account_exports.sole
      expect(export.status).to eq("pending")
      expect(Users::ExportJob).to have_been_enqueued.with(export.id)

      post settings_account_exports_path

      expect(flash[:alert]).to eq(I18n.t("settings.account.export.flash.unavailable"))
      expect(user.account_exports.count).to eq(1)
    end

    it "streams a ready archive to its owner, never through a storage URL" do
      export = ready_export

      get download_settings_account_export_path(export)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/zip")
      expect(response.headers["Content-Disposition"]).to include("attachment", export.filename)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to eq("PK-data")
    end

    it "answers 404 for another account's export and for an expired one" do
      other = ready_export(create(:user))
      expired = ready_export(expires_at: 1.minute.ago)

      get download_settings_account_export_path(other)
      expect(response).to have_http_status(:not_found)

      get download_settings_account_export_path(expired)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the deletion (§4)" do
    let(:confirmation) { { deletion: { username: user.username, acknowledged: "1" } } }

    it "asks for a recent proof of identity first" do
      Session.last.update!(reauthenticated_at: 1.hour.ago)

      post settings_account_deletion_path, params: confirmation

      expect(response).to redirect_to(new_reauthentication_path)
      expect(user.reload).not_to be_deletion_scheduled
    end

    it "requires the username typed again and the acknowledgment" do
      post settings_account_deletion_path, params: { deletion: { username: "someone", acknowledged: "1" } }
      expect(user.reload).not_to be_deletion_scheduled

      post settings_account_deletion_path, params: { deletion: { username: user.username } }
      expect(user.reload).not_to be_deletion_scheduled
      expect(flash[:alert]).to eq(I18n.t("settings.account.deletion.flash.unconfirmed"))
    end

    it "schedules the deletion seven days out, closes the other sessions and mails the date" do
      other = user.sessions.create!(user_agent: "Phone", ip_address: "192.0.2.2", last_seen_at: Time.current)

      post settings_account_deletion_path, params: confirmation

      expect(response).to redirect_to(settings_account_deletion_path)
      expect(user.reload).to have_attributes(deletion_requested_by: "self")
      expect(user.deletion_scheduled_at).to be_within(1.minute).of(7.days.from_now)
      expect(Session.exists?(other.id)).to be(false)
      expect(user.sessions.count).to eq(1)
      expect(enqueued_jobs.map { it["arguments"]&.first(2) }).to include(%w[AccountMailer deletion_scheduled])
    end

    it "leads every page to the deactivated page, which offers to cancel" do
      post settings_account_deletion_path, params: confirmation

      get workouts_path
      expect(response).to redirect_to(settings_account_deletion_path)

      get settings_account_deletion_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings.account.pending.cancel"))

      delete settings_account_deletion_path

      expect(response).to redirect_to(settings_account_path)
      expect(user.reload).not_to be_deletion_scheduled
      get workouts_path
      expect(response).to have_http_status(:ok)
    end

    it "still lets the account download its last export and sign out" do
      export = ready_export
      post settings_account_deletion_path, params: confirmation

      get download_settings_account_export_path(export)
      expect(response).to have_http_status(:ok)

      delete session_path
      expect(response).to redirect_to(new_session_path)
    end

    it "refuses the operator's own account" do
      ENV["INSTANCE_OPERATOR_USERNAME"] = user.username
      post settings_account_deletion_path, params: confirmation

      expect(user.reload).not_to be_deletion_scheduled
      expect(flash[:alert]).to eq(I18n.t("settings.account.deletion.flash.operator"))
    ensure
      ENV.delete("INSTANCE_OPERATOR_USERNAME")
    end

    it "keeps a deletion the operator scheduled out of the account's hands" do
      Users::DeletionSchedule.new(user:).schedule!(by: "operator")
      sign_in_as(user)

      get settings_account_deletion_path
      expect(response.body).to include(CGI.escapeHTML(I18n.t("settings.account.pending.by_operator")))

      delete settings_account_deletion_path
      expect(user.reload).to be_deletion_scheduled
    end

    it "signs out an account whose purge has started" do
      user.update!(deletion_requested_at: 8.days.ago, deletion_scheduled_at: 1.day.ago, deletion_requested_by: "self",
                   deletion_started_at: 1.minute.ago)

      get settings_account_deletion_path

      expect(response).to redirect_to(new_session_path)
    end
  end
end

RSpec.describe "An account in its deletion window (docs/dev/ACCOUNT.md)", type: :request do
  let(:owner) { create(:user) }
  let(:reader) { create(:user, :with_totp) }
  let!(:publication) { create(:workout_publication, workout: create(:workout, user: owner)) }

  before { owner.update!(deletion_requested_at: Time.current, deletion_scheduled_at: 7.days.from_now, deletion_requested_by: "self") }

  it "hides its publications and its profile from every reader" do
    expect(WorkoutPublication.visible_to(reader)).not_to include(publication)
    principal = Workouts::PublicationPrincipal.browser(reader)
    expect(Workouts::PublicationPolicy.new(publication:, principal:).allowed?).to be(false)

    sign_in_as(reader)
    get profile_path(owner.username)

    expect(response).to have_http_status(:not_found)
  end

  it "shows them again once the deletion is cancelled" do
    Users::DeletionSchedule.new(user: owner).cancel!

    expect(WorkoutPublication.visible_to(reader)).to include(publication)
  end

  it "refuses its API tokens with a dedicated problem" do
    get api_rest_v1_me_path, headers: api_headers_for(owner)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["code"]).to eq("account_deletion_scheduled")
  end

  it "creates no notification on its behalf" do
    Notifications::Create.new(user: owner, kind: "follow_request", actor: create(:actor), subject: create(:following)).call!

    expect(owner.notifications).to be_empty
  end
end
