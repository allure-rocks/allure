# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The owner's view of a publication and of a publish preview
      # (docs/dev/API.md). A publication is identified by its own
      # ShortUUID, the same one its ActivityPub object carries.
      module PublicationSerializers
        # The optional fields a profile shares or leaves out, as the web lists
        # them under the §19.1 sentence (WorkoutsHelper#publication_preview_fields).
        OPTIONAL_FIELDS = %w[title description metrics route gpx records route_image device commute weather].freeze

        module_function

        def publication(publication)
          base = Allure::Federation.config.base_url
          workout = publication.workout
          {
            id: publication.to_param,
            workout_id: workout&.to_param,
            audience: publication.audience,
            status: publication.status,
            publishing_profile_id: (Allure::ShortId.encode(publication.publishing_profile.uuid) if publication.publishing_profile),
            published_at: Formats.time(publication.published_at),
            scheduled_for: Formats.time(publication.scheduled_for),
            object_uri: publication.object_uri,
            links: {
              self: "#{base}/api/rest/v1/publications/#{publication.to_param}",
              web: (workout && "#{base}/workouts/#{workout.to_param}?as=publication&audience=#{publication.audience}")
            }
          }
        end

        # What publishing `workout` with `profile` would share, and whether it
        # can: the readiness the web's publish form shows.
        def preview(profile, readiness)
          settings = profile.settings
          shared, not_shared = OPTIONAL_FIELDS.partition do |field|
            field == "metrics" ? Array(settings["metrics"]).any? : settings[field]
          end
          ready = profile.publishable? && readiness.ready?
          codes = readiness.warnings.map(&:to_s)
          {
            publishing_profile_id: Allure::ShortId.encode(profile.uuid),
            audience: profile.audience,
            publishable: ready,
            refusals: ready ? [] : codes,
            warnings: ready ? codes : [],
            shared:,
            not_shared:,
            metrics: Array(settings["metrics"]),
            delay: PublishingProfile::PUBLISH_DELAYS.key(profile.publish_delay_seconds),
            copy: copy(shared)
          }
        end

        # The §19.1 and §19.2 sentences in English, for the client to show
        # before it publishes (docs/dev/API.md).
        def copy(shared = nil)
          I18n.with_locale(:en) do
            labels = Array(shared).map { I18n.t("publishing_profiles.settings.#{it == 'metrics' ? 'metrics_title' : it}") }
            {
              shared: (I18n.t("workouts.publish.preview.shared", fields: labels.join(", ")) if labels.any?),
              never: I18n.t("workouts.publish.preview.never"),
              irrevocable: I18n.t("workouts.publication.confirm.body")
            }.compact
          end
        end
      end
    end
  end
end
