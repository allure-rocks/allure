# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The small representations of PLAN_API.md §6.1–6.2: the account, the
      # sport catalog, equipment and publishing profiles.
      module CatalogSerializers
        module_function

        def me(user, token)
          {
            username: user.username,
            display_name: user.display_name,
            handle: user.handle,
            locale: user.locale,
            unit_system: user.unit_system,
            time_zone: user.time_zone,
            week_start: user.week_start,
            discoverable: user.discoverable,
            heart_rate_profile: HeartRateSerializer.profile(user),
            token: {
              id: token.to_param,
              name: token.name,
              scopes: token.scopes,
              expires_at: Formats.time(token.expires_at)
            }
          }
        end

        def sport(sport)
          {
            slug: sport.slug,
            family: sport.colour_group,
            virtual: sport.virtual,
            pace_basis_metres: sport.pace_basis_metres,
            records_elevation: sport.records_elevation,
            records_power: sport.records_power,
            labels: I18n.available_locales.to_h { [ it, I18n.t("sports.#{sport.slug}", locale: it, default: sport.label) ] }
          }
        end

        def equipment(equipment)
          {
            id: equipment.to_param,
            label: equipment.label,
            description: equipment.description,
            type: equipment.equipment_type.slug,
            active: equipment.is_active,
            total_distance: Formats.number(equipment.total_distance),
            total_elapsed_time: equipment.total_duration,
            total_moving_time: equipment.total_moving,
            total_workouts: equipment.total_workouts,
            created_at: Formats.time(equipment.created_at),
            updated_at: Formats.time(equipment.updated_at)
          }
        end

        def publishing_profile(profile)
          {
            id: Allure::ShortId.encode(profile.uuid),
            name: profile.name,
            audience: profile.audience,
            built_in: profile.built_in?,
            publish_delay: profile.publish_delay_seconds,
            auto_publish: profile.auto_publish,
            publishable: profile.publishable?
          }
        end
      end
    end
  end
end
