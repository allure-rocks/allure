# frozen_string_literal: true

require "rails_helper"

# The comments card and its gestures (PLAN_COMMENTS.md §11, DESIGN.md §10.20):
# every gesture re-renders the card inside its Turbo Frame and returns to the
# thread without one; denial is 404, a closed thread or a refused text
# re-renders the card with its explanation.
RSpec.describe "Comments" do
  let(:owner) { create(:user, username: "marie", display_name: "Marie Dufour") }
  let(:viewer) { create(:user, username: "paul", display_name: "Paul Martin") }
  let(:workout) { create(:workout, user: owner, title: "Col du Galibier") }

  def publish!(target = workout, **attributes)
    create(:workout_publication, workout: target, publishing_profile: public_publishing_profile_for(target.user),
                                 **attributes)
  end

  def frame_headers(target = workout) = { "Turbo-Frame" => "comments-workout-#{target.to_param}" }

  def post_comment(body: "Belle sortie !", parent: nil, headers: frame_headers)
    post workout_comments_path(workout), params: { comment: { body:, parent_id: parent&.to_param } }, headers:
  end

  def comment_by(user, body: "Bravo", parent: nil)
    Comments::Post.new(user:, target: workout, body:, parent_id: parent&.to_param).call!
  end

  def card = response.parsed_body.at_css("turbo-frame#comments-workout-#{workout.to_param} .allure-comments")

  describe "the workout page" do
    it "gives a member the thread, the composer, and the mandatory sentence" do
      publish!
      comment_by(owner, body: "Merci d'être passés")
      sign_in_as(viewer)

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      section = response.parsed_body.at_css("section#comments")
      expect(section).to be_present
      expect(section.text).to include("1 commentaire", "Merci d'être passés", "Marie Dufour", "@marie")
      expect(section.at_css("textarea[name='comment[body]'][maxlength='2000']")).to be_present
      expect(section.text).to include(
        "Votre commentaire est visible par toutes les personnes qui voient cette activité, " \
        "ici et sur les autres instances qui l'ont reçue."
      )
      expect(section.text).not_to include("Fermer les commentaires")
    end

    it "gives the owner the switch and no card before the first publication" do
      sign_in_as(owner)

      get workout_path(workout)
      expect(response.parsed_body.at_css("section#comments")).to be_nil

      publish!
      get workout_path(workout)
      expect(response.parsed_body.at_css("section#comments").text).to include("Fermer les commentaires",
                                                                               "Pas encore de commentaire")
    end

    it "keeps the thread readable for the owner once the publication is gone, and for nobody else" do
      publication = publish!
      comment_by(viewer, body: "Superbe montée")
      publication.mark_deleted!

      sign_in_as(owner)
      get workout_path(workout)
      section = response.parsed_body.at_css("section#comments")
      expect(section.text).to include("Superbe montée", "Cette activité n'est plus publiée")
      expect(section.at_css("textarea")).to be_nil
      expect(section.text).not_to include("Fermer les commentaires")
    end

    it "explains a thread closed by the profile to the owner and closes it for readers" do
      publish!(comments_closed: true)

      sign_in_as(owner)
      get workout_path(workout)
      expect(response.parsed_body.at_css("section#comments").text)
        .to include("Le profil de publication « Profil public » ferme les commentaires.")

      sign_in_as(viewer)
      get workout_path(workout)
      section = response.parsed_body.at_css("section#comments")
      expect(section.text).to include("Les commentaires sont fermés sur cette activité.")
      expect(section.at_css("textarea")).to be_nil
    end

    it "keeps a deactivated author's comment without naming them" do
      publish!
      author = create(:user, username: "lea", display_name: "Léa Roux")
      comment_by(author, body: "Quelle montée")
      author.update!(suspended_at: Time.current)
      sign_in_as(viewer)

      get workout_path(workout)

      section = response.parsed_body.at_css("section#comments")
      expect(section.text).to include("Quelle montée", "Un compte indisponible")
      expect(section.text).not_to include("Léa Roux", "@lea")
      expect(section.at_css("a[href='/@lea']")).to be_nil
    end

    it "escapes the text and keeps its line breaks" do
      publish!
      comment_by(viewer, body: "<script>alert(1)</script>\nDeuxième ligne")
      sign_in_as(owner)

      get workout_path(workout)

      body = response.parsed_body.at_css("section#comments .allure-comment__body")
      expect(body.at_css("script")).to be_nil
      expect(body.text).to include("<script>alert(1)</script>")
      expect(body.at_css("br")).to be_present
    end
  end

  # DESIGN.md §10.20: below `lg` the workout page carries a button to the
  # thread's own page, beside the reactions under the figures.
  describe "the social row and the thread's page" do
    def social_row = response.parsed_body.at_css(".allure-detail-before-map .allure-social-row")

    it "puts the thread's button and the reactions under the figures, once" do
      publish!
      comment_by(owner, body: "Merci d'être passés")
      sign_in_as(viewer)

      get workout_path(workout)

      expect(response.parsed_body.at_css(".page-header .allure-reactions")).to be_nil
      expect(response.parsed_body.css(".allure-reactions").size).to eq(1)
      button = social_row.at_css("a.allure-social-row__comments")
      expect(button["href"]).to eq(workout_comments_path(workout))
      expect(button["aria-label"]).to eq("Voir le commentaire")
      expect(social_row.at_css(".allure-reactions button")).to be_present
      expect(response.parsed_body.at_css("section#comments")["class"]).to include("d-none", "d-lg-block")
    end

    it "invites the first comment and gives the owner read-only counts" do
      publish!
      sign_in_as(owner)

      get workout_path(workout)

      expect(social_row.at_css("a.allure-social-row__comments").text.squish).to eq("Commenter")
      expect(social_row["class"]).to include("d-lg-none")
      expect(social_row.at_css(".allure-reactions")).to be_nil
    end

    it "has no row on a workout that was never published" do
      sign_in_as(owner)

      get workout_path(workout)

      expect(social_row).to be_nil
    end

    it "renders the thread alone, with its way back" do
      publish!
      comment_by(owner, body: "Merci d'être passés")
      sign_in_as(viewer)

      get workout_comments_path(workout)

      expect(response).to have_http_status(:ok)
      page = response.parsed_body
      # A reader reads the publication's frozen title, never the workout's.
      expect(page.at_css("title").text).to start_with("Commentaires · ")
      expect(page.at_css("title").text).not_to include("Col du Galibier")
      expect(page.at_css(".page-pretitle a")["href"]).to eq(workout_path(workout))
      expect(page.at_css("section#comments")["class"]).not_to include("d-none")
      expect(card.text).to include("Merci d'être passés")
      expect(card.at_css("textarea[name='comment[body]']")).to be_present
      expect(page.at_css("#section-map")).to be_nil
    end

    it "gives the owner the thread's page and its switch" do
      publish!
      sign_in_as(owner)

      get workout_comments_path(workout)

      expect(card.text).to include("Fermer les commentaires")
    end

    it "answers 404 on an unpublished workout and sends a visitor to sign-in" do
      get workout_comments_path(workout)
      expect(response).to redirect_to(new_session_path)

      sign_in_as(viewer)
      get workout_comments_path(workout)
      expect(response).to have_http_status(:not_found)

      sign_in_as(owner)
      get workout_comments_path(workout)
      expect(response).to have_http_status(:not_found)
    end

    it "keeps the thread's page for the owner once the publication is gone, and for nobody else" do
      publication = publish!
      comment_by(viewer, body: "Superbe montée")
      publication.mark_deleted!

      sign_in_as(viewer)
      get workout_comments_path(workout)
      expect(response).to have_http_status(:not_found)

      sign_in_as(owner)
      get workout_comments_path(workout)
      expect(card.text).to include("Superbe montée", "Cette activité n'est plus publiée")
    end
  end

  describe "posting" do
    before { publish! }

    it "redirects an anonymous visitor to sign-in" do
      post_comment

      expect(response).to redirect_to(new_session_path)
      expect(Comment.count).to eq(0)
    end

    it "re-renders the card inside the frame" do
      sign_in_as(viewer)

      expect { post_comment }.to change(Comment, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(card.text).to include("1 commentaire", "Belle sortie !", "Paul Martin")
      expect(card.at_css("textarea[name='comment[body]']").text).to be_empty
    end

    it "returns to the thread without a frame" do
      sign_in_as(viewer)

      post_comment(headers: {})

      expect(response).to redirect_to(workout_comments_path(workout))
    end

    it "answers a top-level comment under it" do
      root = comment_by(owner, body: "Qui vient dimanche ?")
      sign_in_as(viewer)

      post_comment(body: "Moi !", parent: root)

      reply = Comment.last
      expect(reply.parent).to eq(root)
      expect(card.at_css(".allure-comments__replies ##{"comment-#{reply.to_param}"}").text).to include("Moi !")
    end

    it "brings a refused text back into its composer with the reason" do
      root = comment_by(owner)
      sign_in_as(viewer)

      post_comment(body: "   ")
      expect(response).to have_http_status(:unprocessable_content)
      expect(card.at_css("textarea.is-invalid")).to be_present
      expect(card.text).to include("Écrivez quelque chose avant d'envoyer.")

      post_comment(body: "a" * 2_001, parent: root)
      expect(response).to have_http_status(:unprocessable_content)
      reply_composer = card.at_css("#comment-reply-#{root.to_param}")
      expect(reply_composer["class"]).to include("show")
      expect(reply_composer.at_css("textarea.is-invalid").text).to eq("a" * 2_001)
      expect(Comment.count).to eq(1)
    end

    it "explains a thread the owner closed meanwhile" do
      workout.update_column(:comments_closed_at, Time.current)
      sign_in_as(viewer)

      post_comment
      expect(response).to have_http_status(:unprocessable_content)
      expect(card.text).to include("Les commentaires sont fermés sur cette activité.")

      post_comment(headers: {})
      expect(response).to redirect_to(workout_comments_path(workout))
      expect(flash[:alert]).to eq("Les commentaires sont fermés sur cette activité.")
      expect(Comment.count).to eq(0)
    end

    it "slows a flood down and keeps the refused text" do
      sign_in_as(viewer)
      # The test cache is a null store; this answers as a store that counted
      # past the limit.
      allow(WorkoutCommentsController.cache_store).to receive(:increment).and_return(21)

      post_comment(body: "Encore un")

      expect(response).to have_http_status(:too_many_requests)
      expect(card.text).to include("Vous commentez un peu vite.")
      expect(card.at_css("textarea.is-invalid").text).to eq("Encore un")
      expect(Comment.count).to eq(0)
    end

    it "answers 404 on an unpublished workout" do
      other = create(:workout, user: owner)
      sign_in_as(viewer)

      post workout_comments_path(other), params: { comment: { body: "Coucou" } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "taking a comment out" do
    before { publish! }

    it "lets the author delete their comment" do
      comment = comment_by(viewer, body: "Oups")
      sign_in_as(viewer)

      delete comment_path(comment), headers: frame_headers

      expect(response).to have_http_status(:ok)
      expect(comment.reload).to be_deleted
      expect(card.text).not_to include("Oups")

      delete comment_path(comment), headers: frame_headers
      expect(response).to have_http_status(:ok)
    end

    it "lets the owner remove a reader's comment, which its author still sees as removed" do
      comment = comment_by(viewer, body: "Hors sujet")
      sign_in_as(owner)

      delete comment_path(comment), headers: frame_headers

      expect(comment.reload).to be_removed
      expect(card.text).not_to include("Hors sujet")

      sign_in_as(viewer)
      get workout_path(workout)
      section = response.parsed_body.at_css("section#comments")
      expect(section.text).to include("Hors sujet", "Retiré par le propriétaire")
    end

    it "keeps replies under a stub when their root goes" do
      root = comment_by(viewer, body: "Question")
      comment_by(owner, body: "Réponse", parent: root)
      sign_in_as(viewer)

      delete comment_path(root), headers: frame_headers

      expect(card.text).to include("Commentaire supprimé par son auteur.", "Réponse")
      expect(card.text).not_to include("Question")
    end

    it "answers 404 to anyone else" do
      comment = comment_by(viewer)
      sign_in_as(create(:user))

      delete comment_path(comment), headers: frame_headers

      expect(response).to have_http_status(:not_found)
      expect(comment.reload).to be_active
    end

    it "offers delete and remove only where they apply" do
      comment_by(viewer, body: "À moi")
      comment_by(create(:user), body: "À quelqu'un d'autre")

      sign_in_as(viewer)
      get workout_path(workout)
      buttons = response.parsed_body.css("section#comments .allure-comment__actions button").map(&:text).map(&:squish)
      expect(buttons.count("Supprimer")).to eq(1)
      expect(buttons).not_to include("Retirer")

      sign_in_as(owner)
      get workout_path(workout)
      buttons = response.parsed_body.css("section#comments .allure-comment__actions button").map(&:text).map(&:squish)
      expect(buttons.count("Retirer")).to eq(2)
      expect(buttons).not_to include("Supprimer")
    end
  end

  describe "the owner's switch" do
    before { publish! }

    it "closes and reopens the thread" do
      sign_in_as(owner)

      patch workout_comment_thread_path(workout), params: { closed: true }, headers: frame_headers
      expect(workout.reload.comments_closed_at).to be_present
      expect(card.text).to include("Rouvrir les commentaires", "Les commentaires sont fermés sur cette activité.")

      patch workout_comment_thread_path(workout), params: { closed: false }
      expect(response).to redirect_to(workout_comments_path(workout))
      expect(workout.reload.comments_closed_at).to be_nil
    end

    it "answers 404 to a reader" do
      sign_in_as(viewer)

      patch workout_comment_thread_path(workout), params: { closed: true }, headers: frame_headers

      expect(response).to have_http_status(:not_found)
      expect(workout.reload.comments_closed_at).to be_nil
    end
  end

  # PLAN_COMMENTS.md §11.2: the same card on a received note, whose origin
  # hosts the thread.
  describe "on a received note" do
    let(:host) do
      create(:actor, uri: "https://remote.example/users/demo", acct: "demo@remote.example",
                     handle: "demo@remote.example", display_name: "Demo Remote")
    end
    let(:note) { create(:remote_note, actor: host) }
    let(:note_frame) { { "Turbo-Frame" => "comments-remote-note-#{note.id}" } }

    def note_card = response.parsed_body.at_css("turbo-frame#comments-remote-note-#{note.id} .allure-comments")

    it "gives a member the composer with the origin's sentence and sends the comment there" do
      sign_in_as(viewer)

      get remote_note_path(note)
      section = response.parsed_body.at_css("section#comments")
      expect(section.text).to include(
        "Votre commentaire est envoyé à l'instance de @demo@remote.example, " \
        "qui le transmet aux autres instances qui ont reçu cette activité."
      )

      expect {
        post remote_note_comments_path(note), params: { comment: { body: "Superbe !" } }, headers: note_frame
      }.to change(Comment, :count).by(1).and change(FederationOutboxEvent, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(note_card.text).to include("1 commentaire", "Superbe !")
      expect(FederationOutboxEvent.last.audience).to eq("to" => [ host.uri ], "cc" => [])
    end

    it "keeps the origin's copy sentence on a followers note, which is never relayed" do
      note.update_column(:audience, "followers")
      create(:remote_note_recipient, remote_note: note, recipient_actor: Federation::ActorProvisioner.new(user: viewer).call!)
      sign_in_as(viewer)

      get remote_note_path(note)

      expect(response.parsed_body.at_css("section#comments").text).to include(
        "Votre commentaire est envoyé à l'instance de @demo@remote.example, qui en conserve une copie."
      )
    end

    it "renders the host's sanitized words and the reader's refused comment with its reason" do
      create(:comment, workout: nil, remote_note: note, actor: host, uri: "https://remote.example/api/v1/comment/h1",
                       in_reply_to_uri: note.object_uri, body: "Merci",
                       content_html: "<p>Merci <script>alert(1)</script><strong>à tous</strong></p>")
      refused = Comments::Post.new(user: viewer, target: note, body: "Trop tard ?").call!
      refused.reject!(reason: "closed")
      sign_in_as(viewer)

      get remote_note_path(note)

      section = response.parsed_body.at_css("section#comments")
      expect(section.at_css("script")).to be_nil
      expect(section.at_css("strong").text).to eq("à tous")
      expect(section.text).to include("Trop tard ?", "Refusé : les commentaires sont fermés")
      expect(section.css(".allure-comment__actions button").map(&:text).map(&:squish)).not_to include("Retirer")
    end

    it "closes the composer when the origin's profile closed comments" do
      closed = create(:remote_note, actor: host,
                                    representation: note.representation.merge("comments_closed" => true))
      sign_in_as(viewer)

      get remote_note_path(closed)
      expect(response.parsed_body.at_css("section#comments").text).to include("Les commentaires sont fermés")

      post remote_note_comments_path(closed), params: { comment: { body: "Coucou" } },
                                              headers: { "Turbo-Frame" => "comments-remote-note-#{closed.id}" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Comment.count).to eq(0)
    end

    it "answers 404 for a followers note the member does not hold" do
      note.update_column(:audience, "followers")
      sign_in_as(viewer)

      post remote_note_comments_path(note), params: { comment: { body: "Coucou" } }
      expect(response).to have_http_status(:not_found)

      get remote_note_comments_path(note)
      expect(response).to have_http_status(:not_found)
    end

    it "puts the thread's button beside the reactions and renders the thread on its own page" do
      sign_in_as(viewer)

      get remote_note_path(note)
      row = response.parsed_body.at_css(".allure-social-row")
      expect(row.at_css("a.allure-social-row__comments")["href"]).to eq(remote_note_comments_path(note))
      expect(row.at_css(".allure-reactions button")).to be_present
      expect(response.parsed_body.css(".allure-reactions").size).to eq(1)

      get remote_note_comments_path(note)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css(".page-pretitle a")["href"]).to eq(remote_note_path(note))
      expect(note_card.at_css("textarea[name='comment[body]']")).to be_present

      post remote_note_comments_path(note), params: { comment: { body: "Superbe !" } }
      expect(response).to redirect_to(remote_note_comments_path(note))
    end

    it "answers 404 for a deleted note's thread" do
      note.update_columns(status: "deleted", deleted_at: Time.current)
      sign_in_as(viewer)

      get remote_note_comments_path(note)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "around the thread" do
    before { publish! }

    it "counts the thread on the feed card and links to it" do
      comment_by(viewer)
      comment_by(create(:user))
      quiet = create(:workout, user: owner, title: "Sortie calme")
      publish!(quiet)
      sign_in_as(viewer)

      get feed_path(public: 1)

      pills = response.parsed_body.css("a.feed-item__comments")
      expect(pills.size).to eq(1)
      expect(pills.first["href"]).to eq(workout_comments_path(workout))
      expect(pills.first["aria-label"]).to eq("2 commentaires")
    end

    it "notifies the owner and names the gesture" do
      sign_in_as(viewer)
      post_comment

      sign_in_as(owner)
      get notifications_path

      expect(response.body).to include("Paul Martin a commenté votre activité « Col du Galibier »")
    end

    it "honours the notification switch" do
      sign_in_as(owner)
      patch settings_notifications_path, params: { user: { notify_comments: "0" } }

      expect(owner.reload.notify_comments).to be(false)
      comment_by(viewer)
      expect(Notification.where(user: owner, kind: "comment")).to be_empty
    end
  end
end
