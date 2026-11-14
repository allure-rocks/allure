# frozen_string_literal: true

# Presentation of the publication feed (DESIGN.md §8.3, §20.1): one card for a
# local publication and a received note, the author it names, and the day
# separators that explain the stream's order. Everything here works on a
# Federation::FollowingFeed::Item and the shared view duck type.
module FeedsHelper
  # Who published the item: a local account or a remote actor, reduced to what
  # the card header prints. A local handle is `@username` (DESIGN.md §8.3);
  # a remote one keeps its instance, `@user@instance`.
  FeedAuthor = Data.define(:record, :name, :handle, :path, :remote)

  # The card's data, resolved once per item: the snapshot view, where the card
  # links, its media endpoints (light and dark), and what the link is called.
  FeedItem = Data.define(:kind, :view, :href, :image_path, :image_path_dark, :owner_view, :audience, :open_label)

  # The sport catalog, loaded once per request for every card on the page.
  def sport_catalog
    @sport_catalog ||= Sport.catalog
  end

  def feed_author_for(item)
    if item.kind == "local"
      user = item.record.user
      FeedAuthor.new(record: user, name: user.display_name, handle: "@#{user.username}",
                     path: profile_path(user.username), remote: false)
    else
      actor = item.record.actor
      FeedAuthor.new(record: actor, name: actor_name(actor), handle: actor_handle(actor),
                     path: actor_profile_path(actor), remote: true)
    end
  end

  def feed_author_avatar_tag(author, size: "md")
    author.remote ? actor_avatar_tag(author.record, size:) : avatar_tag(author.record, size:)
  end

  # The owner reads their own snapshot, never the live workout: the feed shows
  # exactly what was published (DESIGN.md §8.3). Everyone else goes through
  # the publication policy with their browser principal; the feed itself is
  # members-only (PLAN_MEMBERS_ONLY.md).
  def feed_item_for(item)
    if item.kind == "local"
      workout = item.record
      owner_view = current_user.present? && workout.user_id == current_user.id
      # The feed already kept the narrowest publication the viewer may read.
      publication = item.publication
      view = if owner_view
        Workouts::PublicationView.new(publication,
                                      principal: Workouts::PublicationPrincipal.browser(current_user),
                                      sport_catalog:)
      else
        workout_display(workout, sport_catalog:, publication:)
      end
      FeedItem.new(kind: "local", view:, href: workout_path(workout),
                   image_path: publication_route_image_path(view.publication),
                   image_path_dark: publication_route_image_path(view.publication, theme: "dark"),
                   owner_view:, audience: view.publication.audience,
                   open_label: t("workouts.show.title"))
    else
      note = item.record
      FeedItem.new(kind: "remote", view: Federation::RemoteNoteView.new(note, sport_catalog:),
                   href: remote_note_path(note), image_path: remote_note_route_image_path(note),
                   image_path_dark: remote_note_route_image_path(note, theme: "dark"),
                   owner_view: false, audience: note.audience, open_label: t("remote_notes.open"))
    end
  end

  # Day separators follow the publication instant in the viewer's zone: the
  # stream is ordered by publication, the card shows the activity's own date.
  def feed_zone
    current_user&.time_zone.presence || Time.zone
  end

  def feed_day_for(item)
    item.published_at.in_time_zone(feed_zone).to_date
  end

  # Adjacent items sharing a publication day, in stream order. `chunk_while`
  # never reorders: the SQL order stays authoritative.
  def feed_days(items)
    items.chunk_while { |a, b| feed_day_for(a) == feed_day_for(b) }
         .map { |group| [ feed_day_for(group.first), group ] }
  end

  def feed_day_label(date)
    today = Time.find_zone(feed_zone)&.today || Date.current
    case date
    when today then t("workouts.dates.today")
    when today - 1 then t("workouts.dates.yesterday")
    when today - 2 then t("workouts.dates.day_before_yesterday")
    else l(date, format: (date.year == today.year ? :feed_day : :feed_day_year))
    end
  end

  # The primary metric tiles of a card, at most four (DESIGN.md §8.3, §10.2):
  # a metric the profile withheld has no tile at all.
  def feed_primary_metrics(view)
    workout_metric_items(view).select { |metric| metric[:primary] }.sort_by { |metric| metric[:priority] }
  end

  # A plain-text excerpt of the published description: whitespace collapsed,
  # bounded, escaped by ERB. Never the remote `content_html`.
  FEED_EXCERPT_LENGTH = 300

  def feed_excerpt(text)
    squished = text.to_s.squish
    return if squished.empty?

    squished.truncate(FEED_EXCERPT_LENGTH, separator: " ", omission: "…")
  end
end
