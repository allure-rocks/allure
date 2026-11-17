# frozen_string_literal: true

module Api
  module Rest
    module V1
      # What another account published, as this account may read it
      # (docs/dev/API.md). Built from the publication snapshot or
      # the received note only, never from a live workout; a field the profile
      # did not share is absent, so "hidden" never reads as "not recorded".
      # Received text is plain: no remote HTML ever leaves here.
      module SocialSerializers
        # Snapshot keys copied when shared.
        SHARED_TEXT = %w[title description device].freeze
        SHARED_LISTS = %w[record_types record_distances].freeze

        module_function

        def account(actor)
          return { handle: nil, display_name: nil, local: false, deleted: true, profile_url: nil } if actor.nil? || actor.tombstoned?

          base = Allure::Federation.config.base_url
          if actor.local? && actor.user
            user = actor.user
            { handle: user.handle, display_name: user.display_name, local: true, deleted: false,
              profile_url: "#{base}/@#{user.username}" }
          else
            handle = actor.acct.presence&.delete_prefix("acct:") || actor.handle
            { handle:, display_name: actor.display_name.presence || handle, local: false, deleted: false,
              profile_url: "#{base}/@#{handle}" }
          end
        end

        # `context` carries the page's batched counts: { reactions:, comments: }.
        def publication(publication, viewer:, principal:, context:)
          representation = publication.representation.stringify_keys
          workout = publication.workout
          policy = Workouts::PublicationPolicy.new(publication:, principal:)
          body = {
            id: publication.to_param,
            audience: publication.audience,
            published_at: Formats.time(publication.published_at),
            own: workout.user_id == viewer.user_id,
            author: account(publication.actor),
            sport: representation["sport_slug"],
            started_at: representation["started_at"]
          }
          shared_fields(body, representation)
          body[:metrics] = representation.fetch("metrics", {})
          body[:comments_open] = publication.comments_open?
          body[:comment_count] = context.fetch(:comments).fetch(workout, 0)
          body[:reactions] = reactions(context.fetch(:reactions)[workout])
          base = Allure::Federation.config.base_url
          path = "#{base}/api/rest/v1/publications/#{publication.to_param}"
          body[:links] = {
            self: path,
            web: "#{base}/workouts/#{workout.to_param}",
            track: ("#{path}/track" if policy.allowed?(resource: :track)),
            route_image: ("#{path}/route_image" if publication.route_image_variant("light").present? &&
                                                   policy.allowed?(resource: :route_image))
          }.compact
          body
        end

        def remote_note(note, context:)
          view = Federation::RemoteNoteView.new(note)
          representation = note.representation.stringify_keys
          sport = view.sport
          body = {
            id: Allure::ShortId.encode(note.uuid),
            audience: note.audience,
            published_at: Formats.time(note.published_at || note.received_at),
            own: false,
            author: account(note.actor),
            sport: (sport.slug unless sport.is_a?(Federation::RemoteNoteView::SportFallback)),
            sport_label: note.sport_label,
            started_at: Formats.time(note.started_at),
            origin_url: note.object_uri
          }
          body[:title] = note.title if note.title.present?
          body[:description] = note.description if note.description.present?
          body[:device] = view.device if view.device.present?
          body[:commute] = true if view.commute
          body[:weather] = WeatherSerializer.summary(view.weather) if view.weather
          SHARED_LISTS.each { |key| body[key.to_sym] = representation[key] if representation[key].is_a?(Array) }
          body[:metrics] = representation.fetch("metrics", {})
          body[:comments_open] = !view.comments_closed?
          body[:comment_count] = context.fetch(:comments).fetch(note, 0)
          body[:reactions] = reactions(context.fetch(:reactions)[note])
          body[:media] = media_state(view)
          base = Allure::Federation.config.base_url
          path = "#{base}/api/rest/v1/remote_notes/#{body[:id]}"
          body[:links] = {
            self: path,
            web: "#{base}/remote_notes/#{note.id}",
            track: ("#{path}/track" if view.map_visible?),
            route_image: ("#{path}/route_image" if view.route_image_visible?)
          }.compact
          body
        end

        def feed_item(item, viewer:, principal:, context:)
          if item.kind == "local"
            { type: "publication", publication: publication(item.publication, viewer:, principal:, context:) }
          else
            { type: "remote_note", remote_note: remote_note(item.record, context:) }
          end
        end

        def reactions(summary)
          summary ||= Reactions::Summaries::EMPTY
          { counts: Reaction::KINDS.to_h { [ it, summary.count(it) ] }, mine: summary.mine }
        end

        # A thread entry: a withdrawn root kept for its replies is a stub with
        # no text, and the viewer's own removed or refused comment carries its
        # state but stays theirs to read.
        def comment_entry(entry)
          comment(entry.comment, stub: entry.stub?).merge(replies: entry.replies.map { comment(it, stub: false) })
        end

        def comment(comment, stub:)
          {
            id: comment.to_param,
            audience: comment.audience,
            state: comment.status,
            author: (stub || deactivated?(comment.actor) ? nil : account(comment.actor)),
            body: (stub ? nil : comment.body),
            by_thread_host: comment.by_thread_host?,
            published_at: Formats.time(comment.published_at)
          }
        end

        def deactivated?(actor)
          actor.present? && actor.local? && actor.user.present? && actor.user.deactivated?
        end

        def media_state(view)
          if view.media_cached? then "cached"
          elsif view.media_pending? then "pending"
          elsif view.media_unavailable? then "unavailable"
          else "none"
          end
        end

        def shared_fields(body, representation)
          SHARED_TEXT.each { |key| body[key.to_sym] = representation[key] if representation[key].present? }
          body[:commute] = true if representation["commute"] == true
          body[:weather] = WeatherSerializer.summary(representation["weather"]) if representation["weather"].is_a?(Hash)
          SHARED_LISTS.each { |key| body[key.to_sym] = representation[key] if representation[key].is_a?(Array) }
        end
      end
    end
  end
end
