# frozen_string_literal: true

require "rails_helper"

# Members' help (DESIGN.md §20.20): a handful of concept pages, members-only,
# each written in every locale.
RSpec.describe "Help" do
  let(:topics) { HelpController::TOPICS }

  it "keeps visitors out like every page" do
    get help_path
    expect(response).to redirect_to(new_session_path)

    get help_topic_path("publishing")
    expect(response).to redirect_to(new_session_path)
  end

  it "has a body in every language for every topic" do
    topics.each_value do |topic|
      User::LOCALES.each do |locale|
        expect(Rails.root.join("app/views/help/topics/_#{topic}.#{locale}.html.erb")).to exist
      end
    end
  end

  User::LOCALES.each do |locale|
    context "in #{locale}" do
      before { sign_in_as(create(:user, locale:)) }

      it "lists every topic" do
        get help_path

        expect(response).to have_http_status(:ok)
        topics.each do |slug, topic|
          expect(response.body).to include(help_topic_path(slug))
          expect(response.body).to include(CGI.escapeHTML(I18n.t("help.topics.#{topic}.title", locale:)))
        end
      end

      it "renders every topic in the account's language" do
        other = locale == "fr" ? "en" : "fr"

        topics.each do |slug, topic|
          get help_topic_path(slug)

          expect(response).to have_http_status(:ok)
          expect(response.body).to include(CGI.escapeHTML(I18n.t("help.topics.#{topic}.title", locale:)))
          body = Rails.root.join("app/views/help/topics/_#{topic}.#{other}.html.erb").read
          expect(response.body).not_to include(body.lines.find { it.strip.start_with?("<h2>") }.strip)
        end
      end

      it "links the account menu to the help" do
        get help_path

        expect(response.body).to include(%(data-bridge-item="help"))
      end

      it "links the separate profile-sharing choices and explains the chart reading" do
        get help_topic_path("publishing")

        expect(response.parsed_body.at_css("a[href='#{settings_profile_path}']").text).to eq(I18n.t("settings.profile.title", locale:))
        %w[log_scale reading_hint].each do |key|
          expect(response.parsed_body.text).to include(I18n.t("profile.statistics.#{key}", locale:))
        end
      end
    end
  end

  it "answers 404 for an unknown topic" do
    sign_in_as(create(:user))

    get help_topic_path("nothing-here")

    expect(response).to have_http_status(:not_found)
  end

  # Help repeats the §19 promises through the screens' own strings, so it can
  # never word them differently from the place that makes them.
  {
    "publishing" => %w[workouts.publication.confirm.body settings.profile.sharing.privacy],
    "privacy-zones" => %w[privacy_zones.panel],
    "sharing-beyond" => %w[workouts.publication.confirm.body],
    "segments" => %w[segments.listing.notice segments.leaderboard.residual_risk],
    "training-load" => [ [ "me.training_load.how", 4 ], [ "me.training_load.how", 5 ], "settings.heart_rate.privacy" ]
  }.each do |slug, keys|
    it "quotes the screens' privacy texts on #{slug}" do
      User::LOCALES.each do |locale|
        sign_in_as(create(:user, locale:))
        get help_topic_path(slug)

        keys.each do |key, index|
          text = I18n.t(key, locale:)
          text = text.fetch(index) if index
          expect(response.body).to include(CGI.escapeHTML(text))
        end
        delete session_path
      end
    end
  end
end
