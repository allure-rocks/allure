# frozen_string_literal: true

# Connected services (docs/dev/REMOTE-IMPORTS.md, DESIGN.md §8.6): the hub at
# /connections and one page per remote import source the operator enables,
# plus the account's connections to a source the operator has since disabled,
# which stay stored but inert. Every action is scoped to the current account's
# own connection.
class ConnectionsController < ApplicationController
  before_action :set_no_store
  before_action :set_connection, except: %i[index show]
  before_action :require_enabled, only: %i[link mfa retrieve sync sync_equipment]

  def index
    @cards = cards
  end

  def show
    @cards = cards
    @card = @cards.find { |card| card[:source].key == params[:provider] }
    # A service the operator disabled and the account never linked has no
    # page: an old bookmark or notification lands on the hub instead.
    return redirect_to connections_path if @card.nil?
    return if request.headers["Turbo-Frame"].blank?

    render partial: "connections/live", locals: { card: @card }, layout: false
  end

  def update
    @connection.update!(preference_params)
    back notice: t("settings.connections.update.success")
  end

  def link
    ImportConnections::Linking.new(@connection)
      .start!(email: params[:email], password: params[:password], region: params[:region])
    back notice: t("settings.connections.link.started")
  rescue ImportConnections::Linking::NotAllowed
    back alert: t("settings.connections.link.not_allowed")
  end

  def mfa
    ImportConnections::Linking.new(@connection).submit_code!(params[:code])
    back notice: t("settings.connections.mfa.submitted")
  rescue ImportConnections::Linking::NotAllowed
    back alert: t("settings.connections.link.not_allowed")
  end

  def cancel_link
    ImportConnections::Linking.new(@connection).cancel!
    back notice: t("settings.connections.link.cancelled")
  end

  def retrieve
    fallback = ImportConnections::Providers.supports?(@connection.provider, :fallback_sport)
    sport = fallback ? Sport.find_by(id: params.dig(:retrieval, :sport_id).presence) : nil
    result = ImportConnections::Retrieval.new(
      connection: @connection, from: params.dig(:retrieval, :from), to: params.dig(:retrieval, :to),
      sport:, today: viewer_today
    ).call
    if result.success?
      redirect_to workout_import_path(result.batch), notice: t("workouts.batch_import.create.success")
    else
      redirect_back fallback_location: connection_path(@connection.provider), alert: result.error
    end
  end

  def sync
    ImportConnections::SyncJob.perform_later(@connection, manual: true) if @connection.usable?
    back notice: t("settings.connections.sync.started")
  end

  def sync_equipment
    raise ActiveRecord::RecordNotFound unless ImportConnections::Providers.supports?(@connection.provider, :equipment)

    if @connection.usable?
      @connection.update!(sync_equipment: true)
      ImportConnections::EquipmentSyncJob.perform_later(@connection)
    end
    back notice: t("settings.connections.equipment.started")
  end

  def destroy
    return back(alert: t("settings.connections.link.not_allowed")) if @connection.disconnected? || @connection.unlinking?

    @connection.update!(status: "unlinking", pending_expires_at: nil)
    @connection.import_batches.where(status: %w[queued processing]).find_each(&:cancel!)
    ImportConnections::UnlinkJob.perform_later(@connection, delete_data: params[:delete_data] == "1")
    back notice: t("settings.connections.unlink.started")
  end

  private

  # Every service the account may see: the ones the operator enables, and the
  # one it still holds a connection to after the operator disabled it.
  def cards
    connections = current_user.import_connections.index_by(&:provider)
    Allure::ImportSources.remote.filter_map do |source|
      connection = connections[source.key]
      enabled = Allure::RemoteImports::Config.enabled?(source.key)
      next unless enabled || (connection && !connection.disconnected?)

      connection&.then { ImportConnections::Linking.new(it).expire_stale! }
      { source:, connection: connection || ImportConnection.new(user: current_user, provider: source.key), enabled: }
    end
  end

  def set_connection
    provider = params[:provider].to_s
    raise ActiveRecord::RecordNotFound unless Allure::RemoteImports::Config.providers.include?(provider)

    @connection = ImportConnection.for(current_user, provider)
    raise ActiveRecord::RecordNotFound if @connection.new_record? && action_name != "link"
  end

  def require_enabled
    raise ActiveRecord::RecordNotFound unless @connection.enabled?
  end

  def preference_params
    permitted = params.require(:import_connection).permit(:auto_sync, :fallback_sport_id, :positioned_only)
    permitted[:fallback_sport_id] = nil if permitted[:fallback_sport_id].blank?
    permitted
  end

  def back(**flash)
    redirect_to connection_path(@connection.provider), **flash
  end

  def set_no_store
    response.set_header("Cache-Control", "no-store")
  end
end
