# frozen_string_literal: true

module Admin
  # The « Connexions » tab of the imports panel (docs/dev/REMOTE-IMPORTS.md):
  # every account's connection to a remote import source, its state and sync
  # facts, and the audited operator revocation. Nothing stored encrypted is
  # ever rendered, nor the external account's name or address.
  class ImportConnectionsController < BaseController
    include Pagy::Method

    def index
      @provider = ImportConnection::PROVIDERS.include?(params[:provider]) ? params[:provider] : nil
      @status = ImportConnection::STATUSES.include?(params[:status]) ? params[:status] : nil
      scope = ImportConnection.includes(:user).order(updated_at: :desc, id: :desc)
      scope = scope.where(provider: @provider) if @provider
      scope = scope.where(status: @status) if @status
      @pagy, @connections = pagy(scope, limit: 25)

      ids = @connections.map(&:id)
      @workout_counts = Workout.where(import_connection_id: ids).group(:import_connection_id).count
      @active_batches = WorkoutImportBatch.where(import_connection_id: ids, status: %w[queued processing])
                                          .group(:import_connection_id).count
    end

    def revoke
      connection = ImportConnection.find(params[:id])
      if ImportConnections::OperatorRevocation.new(connection).call!
        Audit.record(actor: current_user, action: :import_connection_revoked, subject: connection,
                     metadata: { "provider" => connection.provider, "owner" => connection.user.username })
        redirect_to admin_import_connections_path, notice: t("admin.imports.connections.flash.revoked")
      else
        redirect_to admin_import_connections_path, alert: t("admin.imports.connections.flash.not_revocable")
      end
    end
  end
end
