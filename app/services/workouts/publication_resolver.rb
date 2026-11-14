# frozen_string_literal: true

module Workouts
  # The one publication of a workout a signed-in reader is served
  # (PLAN_AUDIENCES.md §3): among the active publications, the narrowest
  # audience the reader is entitled to, so a follower reads the followers
  # version and everyone else the public one. `audience:` narrows the choice to
  # that audience — the owner's reader preview of one publication. Nil when
  # nothing serves the reader, which callers turn into a 404.
  class PublicationResolver
    def initialize(workout:, user:, audience: nil)
      @workout = workout
      @user = user
      @audience = audience.presence
    end

    def call
      principal = PublicationPrincipal.browser(@user)
      candidates.find do |publication|
        PublicationPolicy.new(publication:, principal:).allowed?(resource: :workout)
      end
    end

    private

    def candidates
      publications = WorkoutPublication.by_precedence(@workout.active_publications.to_a)
      return publications unless @audience

      publications.select { |publication| publication.audience == @audience }
    end
  end
end
