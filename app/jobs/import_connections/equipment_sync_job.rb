# frozen_string_literal: true

module ImportConnections
  # Brings the provider's gear in as local equipment and attaches it to the
  # connection's workouts that have none (docs/dev/REMOTE-IMPORTS.md). An
  # item is created once, by external id, and never deleted or renamed by a
  # later sync; later imports attach known gear as they arrive.
  class EquipmentSyncJob < ApplicationJob
    MAX_LOOKUPS = 200
    LABEL_LENGTH = 50

    queue_as :remote_imports

    limits_concurrency key: ->(connection) { connection.id.to_s }, group: ImportConnection::CONCURRENCY_GROUP,
                       duration: 30.minutes

    def perform(connection)
      return unless connection.usable?

      I18n.with_locale(connection.user.locale) do
        provider = Providers.for(connection)
        provider.equipment.each { |item| create_equipment(connection, item) }
        attach(connection, provider)
      rescue Allure::RemoteImports::Error::AuthError
        Expiry.new(connection).call
      rescue Allure::RemoteImports::Error
        connection.update!(last_sync_error: I18n.t("settings.connections.errors.unavailable"))
      end
    end

    private

    def create_equipment(connection, item)
      return if connection.equipments.exists?(external_id: item.external_id)

      type = EquipmentType.find_by(slug: item.kind) || EquipmentType.find_by!(slug: "misc")
      connection.user.equipments.create!(
        label: unique_label(connection.user, item),
        equipment_type: type,
        description: [ item.brand, item.model ].compact_blank.join(" ").presence,
        is_active: item.active,
        import_connection: connection,
        external_id: item.external_id
      )
    end

    def unique_label(user, item)
      base = item.name.to_s.strip.presence || [ item.brand, item.model ].compact_blank.join(" ").presence ||
             I18n.t("settings.connections.equipment.untitled")
      base = base.truncate(LABEL_LENGTH, omission: "")
      return base unless user.equipments.exists?(label: base)

      (2..).each do |number|
        suffix = " (#{number})"
        label = base.truncate(LABEL_LENGTH - suffix.length, omission: "") + suffix
        return label unless user.equipments.exists?(label:)
      end
    end

    # The gear of an activity is known from its entry when it was imported
    # with equipment sync on; otherwise the provider is asked, a bounded number
    # of times per run.
    def attach(connection, provider)
      by_external_id = connection.equipments.index_by(&:external_id)
      return if by_external_id.empty?

      lookups = 0
      connection.workouts.where.missing(:equipments).find_each do |workout|
        gear_id = recorded_gear(workout)
        if gear_id.nil? && provider.respond_to?(:equipment_external_id_for) && lookups < MAX_LOOKUPS
          lookups += 1
          gear_id = provider.equipment_external_id_for(workout.external_id)
        end
        equipment = by_external_id[gear_id.to_s]
        Equipments::Totals.sync(workout, [ equipment.id ]) if equipment
      end
    end

    def recorded_gear(workout)
      WorkoutImportEntry.where(workout:).order(:id).last&.metadata.to_h["equipment_external_id"].presence
    end
  end
end
