# frozen_string_literal: true

module Workouts
  # Resolves the sport a file describes, in one place so the importer and the
  # re-detection backfill can never disagree (PLAN_VIRTUAL.md §6). Resolution
  # order: the sport the caller declares (the activity type an athlete chose
  # on another service, PLAN_STRAVA_ARCHIVE.md §4), the file's own signal, the
  # owner's generic-sport default for a detected catch-all, the virtual
  # platform's declared sport when the file carries none, then the caller's
  # fallback.
  class SportResolver
    class MissingSport < StandardError; end

    Resolution = Data.define(:sport, :source)

    # What the file may say more precisely than a declaration: a generic sport
    # refines to one of its curated variants, and a swim to its other venue.
    REFINEMENTS = Sport::DEFAULT_TARGET_SLUGS.merge(
      "open_water_swimming" => %w[pool_swimming],
      "pool_swimming" => %w[open_water_swimming]
    ).freeze

    def initialize(user:, track:, fallback_sport: nil, declared_sport: nil)
      @user = user
      @track = track
      @fallback_sport = fallback_sport
      @declared_sport = declared_sport
    end

    def call
      detection = Allure::ActivityDetector.new.detect(@track)
      return Resolution.new(sport: refined_declaration(detection), source: "declared") if @declared_sport

      detected_sport = Sport.find_by(slug: detection.sport_slug) if detection
      return Resolution.new(sport: preferred_sport(detected_sport, detection), source: "detected") if detected_sport
      return Resolution.new(sport: platform_sport, source: "detected") if platform_sport
      return Resolution.new(sport: @fallback_sport, source: "fallback") if @fallback_sport

      raise MissingSport, "no sport could be resolved for this file"
    end

    private

    # A declared sport is kept unless the file names one of its refinements;
    # a generic one still left then takes the owner's default variant. A swim
    # recorded without any position was not in open water.
    def refined_declaration(detection)
      slug = @declared_sport.slug
      if detection && REFINEMENTS.fetch(slug, []).include?(detection.sport_slug)
        refined = Sport.active.find_by(slug: detection.sport_slug)
        return refined if refined
      end
      if slug == "open_water_swimming" && !@track.positioned?
        pool = Sport.active.find_by(slug: "pool_swimming")
        return pool if pool
      end

      @user.preferred_sport_for(slug) || @declared_sport
    end

    # The owner's generic-sport default refines a detected catch-all
    # (`cycling`, `running`, `walking`); an explicit detection always wins, and
    # the import stays reported as detected.
    def preferred_sport(detected_sport, detection)
      return detected_sport unless detection

      @user.preferred_sport_for(detection.sport_slug) || detected_sport
    end

    # A provider whose FIT sport is ambiguous (an ergometer writing
    # `fitness_equipment`, an export with no sport at all) still states its
    # sport through the platform catalog.
    def platform_sport
      return @platform_sport if defined?(@platform_sport)

      slug = Allure::Virtual::Platforms.for_creator(@track.creator)&.sport_slug
      @platform_sport = slug && Sport.find_by(slug:)
    end
  end
end
