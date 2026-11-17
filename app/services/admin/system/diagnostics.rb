# frozen_string_literal: true

module Admin
  module System
    # Read-only instance diagnostics for the administration console: versions,
    # database sizes, storage totals, environment flags, and instance identity.
    # Never a secret value — flags are booleans, and no key, credential, or
    # connection string is rendered (docs/dev/ADMIN.md).
    class Diagnostics
      Result = Data.define(:versions, :database_sizes, :storage, :environment, :instance)

      def call
        Result.new(
          versions: versions,
          database_sizes: database_sizes,
          storage: storage,
          environment: environment,
          instance: instance
        )
      end

      private

      def versions
        {
          "allure" => Allure::VERSION,
          "ruby" => RUBY_VERSION,
          "rails" => Rails.version,
          "solid_queue" => Gem.loaded_specs["solid_queue"]&.version&.to_s,
          "postgresql" => scalar(primary, "SHOW server_version"),
          "postgis" => scalar(primary, "SELECT PostGIS_Lib_Version()")
        }
      end

      def database_sizes
        {
          "primary" => database_size(primary),
          "queue" => database_size(queue_connection),
          "cable" => database_size(cable_connection)
        }
      end

      def storage
        {
          blobs: ActiveStorage::Blob.count,
          bytes: ActiveStorage::Blob.sum(:byte_size),
          attachments: ActiveStorage::Attachment.group(:record_type).count
        }
      end

      def environment
        {
          registration_open: Allure::Registration.open?,
          federation_enabled: Allure::Federation::Config.enabled?,
          restricted_federation: ENV["FEDERATION_RESTRICTED_ENABLED"] == "true",
          operator_configured: ENV.fetch("INSTANCE_OPERATOR_USERNAME", "").strip.present?,
          smtp_configured: ENV["SMTP_ADDRESS"].present?,
          remote_imports: Allure::RemoteImports::Config.providers.index_with { Allure::RemoteImports::Config.enabled?(it) },
          federation_base_url: Allure::Federation.config.base_url,
          federation_domain: Allure::Federation.config.domain
        }
      end

      def instance
        {
          name: Allure::Instance.name,
          description: Allure::Instance.description,
          host_name: Allure::Instance.host_name,
          host_url: Allure::Instance.host_url
        }
      end

      def primary = ActiveRecord::Base.connection
      def queue_connection = SolidQueue::Record.connection
      def cable_connection = SolidCable::Record.connection

      def scalar(connection, sql)
        connection.select_value(sql).to_s
      rescue StandardError => error
        report(error)
        nil
      end

      def database_size(connection)
        value = connection.select_value("SELECT pg_database_size(current_database())")
        value.to_i
      rescue StandardError => error
        report(error)
        nil
      end

      def report(error)
        Rails.error.report(error, handled: true, context: { component: self.class.name })
      end
    end
  end
end
