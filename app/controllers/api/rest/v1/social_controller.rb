# frozen_string_literal: true

module Api
  module Rest
    module V1
      # Social reads (PLAN_API.md §6.5, §10): the feed, publications and
      # received notes, their threads and reactions, and the account's
      # relationships. Every read goes through the service or policy the web
      # page uses, with the token's account as a signed-in browser reader, so
      # the API never shows more than the website does.
      class SocialController < BaseController
        include SocialReading

        require_scope "social:read"

        # The web's feed: the account's own publications, followed accounts,
        # entitled received notes, and the instance's public publications
        # while `public` is on (by default when the account follows nobody).
        def feed
          feed = Federation::FollowingFeed.new(actor: viewer_actor, include_public: include_public?)
          limit = page_limit
          scope = feed.relation
          if params[:cursor].present?
            published_at, kind, id = feed_cursor
            scope = scope.where("(following_feed_items.published_at, following_feed_items.kind, following_feed_items.id) < (?, ?, ?)",
                                published_at, kind, id)
          end
          rows = scope.order(Arel.sql("following_feed_items.published_at DESC, following_feed_items.kind DESC, " \
                                      "following_feed_items.id DESC")).limit(limit + 1).to_a
          more = rows.size > limit
          rows = rows.first(limit)
          # A row whose record went away between the two queries is skipped.
          items = feed.items_for(rows).select(&:record)
          context = reading_context(items.map(&:record))
          last = rows.last
          render json: {
            data: items.map { SocialSerializers.feed_item(it, viewer: viewer_actor, principal:, context:) },
            next_cursor: (Cursor.encode([ "#{last.published_at.utc.iso8601(6)}|#{last.kind}", last.id ], context: "feed") if more)
          }
        end

        # The owner's view of every thread of their workout, or one audience's.
        def workout_comments
          workout = current_user.workouts.find_by_short_id!(params[:workout_id])
          audiences = params[:audience].presence ? [ audience_param ] : nil
          listing = Comments::Listing.new(target: workout, viewer: viewer_actor, audiences:).call
          render json: { data: listing.entries.map { SocialSerializers.comment_entry(it) } }
        end

        # Counts per reaction type, as the owner's page shows them; the web
        # names nobody, so neither does the API.
        def workout_reactions
          workout = current_user.workouts.find_by_short_id!(params[:workout_id])
          summary = Reactions::Summaries.new(targets: [ workout ], viewer: viewer_actor).call[workout]
          render json: SocialSerializers.reactions(summary)
        end

        def followers
          relationships(Following.accepted_followers_of(viewer_actor), :follower_actor)
        end

        def following
          relationships(Following.accepted_following_of(viewer_actor), :followed_actor)
        end

        private

        # The feed's order is (published_at, kind, id), all descending.
        def feed_cursor
          key, id = Cursor.decode(params[:cursor], context: "feed")
          published_at, kind = key.to_s.split("|", 2)
          [ Time.iso8601(published_at.to_s), kind, id ]
        rescue ArgumentError
          raise Cursor::Invalid
        end

        def include_public?
          case params[:public].to_s
          when "true" then true
          when "false" then false
          when "" then !Following.accepted_following_of(viewer_actor).exists?
          else raise InvalidParameter, "public"
          end
        end

        def audience_param
          value = params[:audience].to_s
          raise InvalidParameter, "audience" unless Comment::AUDIENCES.include?(value)

          value
        end

        def relationships(scope, side)
          scope = scope.joins(side).merge(Actor.where(tombstoned_at: nil)).includes(side => :user)
          render json: paginate(scope, column: :created_at, direction: :desc, context: "relationships:#{side}") { |following|
            SocialSerializers.account(following.public_send(side)).merge(since: Formats.time(following.created_at))
          }
        end
      end
    end
  end
end
