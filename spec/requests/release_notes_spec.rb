# frozen_string_literal: true

require "rails_helper"

# Release notes: the footer version line, the what's-new dialog, and the
# per-account acknowledgement it records (DESIGN.md §10.9, §7.5).
RSpec.describe "Release notes" do
  let(:user) { create(:user) }
  let(:notes) { Allure::ReleaseNotes.for(version: Allure::VERSION, locale: :fr) }

  describe "anonymous visitor" do
    it "redirects to sign-in and renders no dialog" do
      get feed_path

      expect(response).to redirect_to(new_session_path)
      expect(response.body).not_to include("release-notes-modal")
    end
  end

  describe "signed-in account" do
    before { sign_in_as(user) }

    it "auto-shows the dialog when the release has not been seen" do
      user.update_column(:release_notes_seen_version, nil)

      get me_path

      expect(response.body).to include('id="release-notes-modal"')
      expect(response.body).to include('data-release-notes-auto-show-value="true"')
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("release_notes.title")),
        ERB::Util.html_escape(notes.first)
      )
      expect(response.body).to include('aria-haspopup="dialog"')
    end

    it "keeps the reopen trigger but stops the auto-show once acknowledged" do
      get me_path

      expect(response.body).to include('id="release-notes-modal"')
      expect(response.body).to include('data-release-notes-auto-show-value="false"')
      expect(response.body).to include('aria-haspopup="dialog"')
    end

    it "renders the dialog in English when asked" do
      get me_path(locale: "en")

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("release_notes.title", locale: :en)))
      expect(response.body).to include(I18n.t("release_notes.footer_version", version: Allure::VERSION, locale: :en))
    end

    it "records the acknowledgement" do
      user.update_column(:release_notes_seen_version, nil)

      patch release_notes_path

      expect(response).to have_http_status(:no_content)
      expect(user.reload.release_notes_seen_version).to eq(Allure::VERSION)
    end
  end

  describe "release without curated notes" do
    before do
      allow(Allure::ReleaseNotes).to receive(:for).and_return([])
      sign_in_as(user)
    end

    it "keeps the footer plain and renders no dialog" do
      get me_path

      expect(response.body).to include(I18n.t("release_notes.footer_version", version: Allure::VERSION))
      expect(response.body).not_to include("release-notes-modal")
    end
  end

  describe "authentication" do
    it "requires a session to acknowledge" do
      patch release_notes_path

      expect(response).to redirect_to(new_session_path)
    end
  end
end
