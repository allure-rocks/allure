# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Notifications" do
  let(:user) { create(:user) }
  let(:local) { Federation::ActorProvisioner.new(user:).call! }
  let(:remote) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      acct: "demo@remote.example",
      handle: "demo"
    )
  end
  let(:following) { create(:following, follower_actor: remote, followed_actor: local) }
  let!(:notification) { create(:notification, user:, actor: remote, subject: following) }

  it "redirects anonymous visitors to sign-in" do
    get notifications_path

    expect(response).to redirect_to(new_session_path)
  end

  describe "signed in" do
    before { sign_in_as(user) }

    it "lists only the current account's notifications" do
      other = create(:notification)

      get notifications_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(notification_path(notification))
      expect(response.body).not_to include(notification_path(other))
    end

    it "keeps notification links out of Turbo prefetch and frame navigation" do
      get notifications_path

      expect(response.body).to include(%(data-turbo-prefetch="false"), %(data-turbo-frame="_top"))
    end

    it "filters to unread notifications" do
      notification.mark_read!
      second = create(
        :notification,
        user:,
        actor: create(:actor),
        subject: create(:following, follower_actor: create(:actor), followed_actor: local)
      )

      get notifications_path(filter: "unread")

      expect(response.body).to include(notification_path(second))
      expect(response.body).not_to include(notification_path(notification))
    end

    it "marks a request notification read and opens the decisions hub" do
      get notification_path(notification)

      expect(response).to redirect_to(people_path)
      expect(notification.reload).to be_read
    end

    it "marks an accepted notification read and opens the account" do
      accepted = create(
        :notification,
        :accepted,
        user:,
        actor: remote,
        subject: create(:following, :accepted, follower_actor: local, followed_actor: remote)
      )

      get notification_path(accepted)

      expect(response).to redirect_to(remote_profile_path("demo@remote.example"))
      expect(accepted.reload).to be_read
    end

    it "names the activation notice after the frozen publication and opens its workout" do
      publication = create(:workout_publication)
      WorkoutPublication.where(id: publication.id)
        .update_all(representation: publication.representation.merge("title" => "Morning ride"))
      publication.reload
      activated = create(:notification, :publication_activated, user:, subject: publication)

      get notification_path(activated)

      expect(response).to redirect_to(workout_path(publication.workout))
      expect(activated.reload).to be_read

      get notifications_path
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("notifications.kinds.publication_activated", title: "Morning ride"))
      )
    end

    it "describes automatic publications and opens the workout's sharing card" do
      publication = create(:workout_publication)
      WorkoutPublication.where(id: publication.id)
        .update_all(representation: publication.representation.merge("title" => "Morning ride"))
      publication.reload
      published = create(:notification, user:, kind: "auto_published", actor: nil, subject: publication,
                                        payload: { "audience" => "public" })
      row = publication.workout.auto_publications.create!(audience: "public", deadline_at: Time.current,
                                                           status: "failed", reason: "enrichment_timeout", settled_at: Time.current)
      failed = create(:notification, user:, kind: "auto_publication_failed", actor: nil, subject: row,
                                     payload: { "reason" => "enrichment_timeout" })

      get notification_path(published)
      expect(response).to redirect_to(workout_path(publication.workout, anchor: "section-sharing"))
      get notification_path(failed)
      expect(response).to redirect_to(workout_path(publication.workout, anchor: "section-sharing"))

      get notifications_path
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("notifications.kinds.auto_published", title: "Morning ride")),
        ERB::Util.html_escape(I18n.t("notifications.kinds.auto_publication_failed", title: publication.workout.title))
      )
    end

    it "names the reaction gesture and opens the workout" do
      workout = create(:workout, user:, title: "Sortie du soir")
      create(:reaction, :beer, workout:, actor: remote)
      notice = create(:notification, user:, kind: "reaction", actor: remote, subject: workout,
                                     payload: { "count" => 1, "kinds" => { "beer" => 1 } })

      get notification_path(notice)

      expect(response).to redirect_to(workout_path(workout))
      expect(notice.reload).to be_read

      get notifications_path
      expect(response.body).to include(
        ERB::Util.html_escape(
          I18n.t("notifications.kinds.reaction_beer", name: "demo", title: "Sortie du soir")
        )
      )
    end

    it "names the newest account and counts the others for several reactions" do
      workout = create(:workout, user:, title: "Sortie du soir")
      create(:notification, user:, kind: "reaction", actor: remote, subject: workout,
                            payload: { "count" => 60, "kinds" => { "beer" => 20, "like" => 40 } })

      get notifications_path

      expect(response.body).to include(
        ERB::Util.html_escape(
          I18n.t("notifications.kinds.reaction_many", name: "demo", title: "Sortie du soir", count: 59)
        )
      )
    end

    it "falls back to the inbox for an orphaned reaction notice" do
      notice = create(:notification, user:, kind: "reaction", actor: remote, subject: nil)

      get notification_path(notice)

      expect(response).to redirect_to(notifications_path)

      get notifications_path
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("notifications.kinds.reaction_unavailable", name: "demo"))
      )
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("notifications.kinds.reaction_deleted")))
    end

    it "keeps the deleted-account copy when the reacting account is gone" do
      create(:notification, user:, kind: "reaction", actor: nil, subject: nil)

      get notifications_path

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("notifications.kinds.reaction_deleted")))
    end

    it "uses the deleted-account copy for a tombstoned reacting account" do
      gone = create(:local_actor)
      create(:notification, user:, kind: "reaction", actor: gone, subject: nil)
      gone.tombstone!

      get notifications_path

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("notifications.kinds.reaction_deleted")))
    end

    it "names a kept credit whose source was deleted and opens it" do
      credit = create(:workout, :credit, user:, title: "Sortie du soir", credited_from: nil, credited_by: remote,
                                         credit_detached_at: Time.current)
      notice = create(:notification, user:, kind: "participation_source_deleted", actor: nil, subject: credit)

      get notification_path(notice)
      expect(response).to redirect_to(workout_path(credit))

      get notifications_path
      expect(response.body).to include(ERB::Util.html_escape(
        I18n.t("notifications.kinds.participation_source_deleted", title: "Sortie du soir")
      ))
    end

    it "names the participation invitation and opens the workout" do
      workout = create(:workout, user:, title: "Sortie du soir")
      participation = create(:workout_participation, :pending, workout:)
      notice = create(:notification, user:, kind: "participation_requested", actor: remote, subject: participation)

      get notification_path(notice)

      expect(response).to redirect_to(workout_path(workout))
      expect(notice.reload).to be_read

      get notifications_path
      expect(response.body).to include(
        ERB::Util.html_escape(
          I18n.t("notifications.kinds.participation_requested", name: "demo", title: "Sortie du soir")
        )
      )
    end

    it "names a comment on the owner's workout and opens the comment" do
      workout = create(:workout, user:, title: "Sortie du soir")
      comment = create(:comment, workout:, actor: remote, uri: "https://remote.example/api/v1/comment/1")
      notice = create(:notification, user:, kind: "comment", actor: remote, subject: comment)

      get notification_path(notice)

      expect(response).to redirect_to(workout_comments_path(workout, anchor: "comment-#{comment.to_param}"))

      get notifications_path
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("notifications.kinds.comment", name: "demo", title: "Sortie du soir"))
      )
    end

    it "names a reply to the recipient's own comment without the workout's title" do
      other_workout = create(:workout, title: "Titre privé")
      root = create(:comment, workout: other_workout, actor: local)
      reply = create(:comment, workout: other_workout, actor: remote, parent: root, in_reply_to_uri: root.uri,
                               uri: "https://remote.example/api/v1/comment/2")
      create(:notification, user:, kind: "comment", actor: remote, subject: reply)

      get notifications_path

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("notifications.kinds.comment_reply", name: "demo")))
      expect(response.body).not_to include("Titre privé")
    end

    it "falls back to the inbox for a comment that no longer exists" do
      notice = create(:notification, user:, kind: "comment", actor: remote, subject: nil)

      get notification_path(notice)
      expect(response).to redirect_to(notifications_path)

      get notifications_path
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("notifications.kinds.comment_deleted")))
    end

    it "falls back to the inbox for an orphaned participation notice" do
      notice = create(:notification, user:, kind: "participation_confirmed", actor: remote, subject: nil)

      get notification_path(notice)

      expect(response).to redirect_to(notifications_path)

      get notifications_path
      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t("notifications.kinds.participation_confirmed_unavailable", name: "demo"))
      )
      expect(response.body).not_to include(
        ERB::Util.html_escape(I18n.t("notifications.kinds.participation_confirmed_deleted"))
      )
    end

    it "falls back to the inbox when an activation subject is gone" do
      orphan = create(:notification, :publication_activated, user:, subject: nil)

      get notification_path(orphan)

      expect(response).to redirect_to(notifications_path)
    end

    it "returns 404 for another account's notification" do
      other = create(:notification)

      get notification_path(other)

      expect(response).to have_http_status(:not_found)
      expect(other.reload).not_to be_read
    end

    it "serves the badge partial without caching" do
      get badge_notifications_path, headers: { "Turbo-Frame" => "notification-badge" }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("badge bg-red")
      expect(response.body).to match(/data-label="Notifications, \d+ non lues?"/)
      expect(response.body).not_to include("<html")
    end

    it "serves the dropdown frame with the latest notifications" do
      get menu_notifications_path, headers: { "Turbo-Frame" => "notification-menu" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="notification-menu"), notification_path(notification))
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    it "marks all of the current account's notifications read" do
      other = create(:notification)

      post mark_all_read_notifications_path

      expect(response).to redirect_to(notifications_path)
      expect(notification.reload).to be_read
      expect(other.reload).not_to be_read
    end

    it "shows the bell in the topbar" do
      get feed_path

      expect(response.body).to include(%(id="notification-badge"), %(data-controller="notification-menu"))
    end
  end
end
