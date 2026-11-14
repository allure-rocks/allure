# frozen_string_literal: true

module Allure
  class ActivityDetector
    Candidate = Data.define(:sport_slug, :source, :value, :confidence, :alias_length)
    Detection = Data.define(:sport_slug, :source, :value, :confidence)

    SOURCE_CONFIDENCE = {
      # FIT carries a real sport/sub_sport enumeration rather than free-form
      # text, so it is the most reliable signal available. Its parser emits
      # exactly one signal per file; two at this confidence would resolve to
      # different sports and trigger the ambiguity guard below.
      fit_sport: 100,
      osmand_activity: 100,
      gpx_track_type: 100,
      # TCX declares the sport per activity like FIT and GPX track type do.
      tcx_sport: 100,
      osmand_route: 90,
      gpx_keywords: 80,
      gpx_metadata_name: 55,
      gpx_metadata_description: 45,
      track_name: 55,
      track_description: 45,
      kml_name: 55,
      kml_description: 45,
      creator: 30
    }.freeze
    AUTOMATIC_THRESHOLD = 45

    def detect(track)
      candidates = signals_for(track)
        .flat_map { |signal| candidates_for(signal) }
        .group_by { |candidate| [ candidate.source, candidate.value ] }
        .values
        .flat_map do |signal_candidates|
          longest_alias = signal_candidates.map(&:alias_length).max
          signal_candidates.select { |candidate| candidate.alias_length == longest_alias }
        end
      strongest = candidates.group_by(&:sport_slug).values.filter_map do |sport_candidates|
        sport_candidates.max_by { |candidate| [ candidate.confidence, candidate.alias_length ] }
      end.sort_by { |candidate| [ -candidate.confidence, -candidate.alias_length ] }
      best = strongest.first
      second = strongest.second

      return unless best
      return if best.confidence < AUTOMATIC_THRESHOLD
      return if second && second.confidence == best.confidence

      Detection.new(
        sport_slug: best.sport_slug,
        source: best.source,
        value: best.value,
        confidence: best.confidence
      )
    end

    private

    def signals_for(track)
      track.activity_signals + [
        Allure::Gpx::ActivitySignal.new(source: :track_name, value: track.name),
        Allure::Gpx::ActivitySignal.new(source: :track_description, value: track.description),
        Allure::Gpx::ActivitySignal.new(source: :creator, value: track.creator)
      ].reject { |signal| signal.value.blank? }
    end

    def candidates_for(signal)
      source_confidence = SOURCE_CONFIDENCE.fetch(signal.source, 0)
      return [] if source_confidence.zero?

      signal.value.to_s.split(/[,;|]/).flat_map do |value|
        normalized_value = normalize(value)
        next [] if normalized_value.blank?

        aliases.filter_map do |alias_value, sport_slug|
          next unless matches?(normalized_value, alias_value)

          Candidate.new(
            sport_slug: sport_slug,
            source: signal.source,
            value: value.strip,
            confidence: source_confidence,
            alias_length: alias_value.count("_") + 1
          )
        end
      end
    end

    def aliases
      @aliases ||= ActivityTypeCatalog::SPORT_ALIASES.each_with_object({}) do |(sport_slug, values), result|
        values.each { |value| result[normalize(value)] = sport_slug }
      end
    end

    def matches?(value, alias_value)
      return true if value == alias_value

      /(?:\A|_)#{Regexp.escape(alias_value)}(?:\z|_)/.match?(value)
    end

    def normalize(value)
      value.to_s
        .unicode_normalize(:nfkd)
        .gsub(/\p{Mn}/, "")
        .downcase
        .gsub(/[^a-z0-9]+/, "_")
        .gsub(/\A_+|_+\z/, "")
        .gsub(/_+/, "_")
    end
  end
end
