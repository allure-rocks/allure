# frozen_string_literal: true

module ImportConnectionsHelper
  STATE_STYLES = {
    "disconnected" => "bg-secondary-lt",
    "linked" => "bg-success-lt",
    "expired" => "bg-warning-lt",
    "revoked" => "bg-warning-lt",
    "pending" => "bg-primary-lt",
    "mfa_pending" => "bg-primary-lt",
    "unlinking" => "bg-secondary-lt",
    "disabled" => "bg-secondary-lt"
  }.freeze

  # A source's mark (DESIGN.md §6.4): the provider's own inline SVG when one
  # ships under `import_sources/icons/`, otherwise its Tabler glyph.
  def import_source_icon_tag(source)
    if lookup_context.exists?(source.key, [ "import_sources/icons" ], true)
      tag.span(render("import_sources/icons/#{source.key}"), class: "import-source-icon me-1", aria: { hidden: true })
    else
      tag.i(class: "ti ti-#{source.icon} me-1", aria: { hidden: true })
    end
  end

  # The card's state (DESIGN.md §8.6): what the account sees of a connection.
  def import_connection_state(connection, enabled:)
    return "disabled" unless enabled
    return "disconnected" if connection.disconnected?

    connection.status
  end

  # A state the card keeps refreshing for: a link or an unlink in progress.
  # Awaiting a verification code is not one — the owner is typing it.
  def import_connection_transitional?(connection)
    return false if connection.new_record?
    return true if connection.unlinking? || connection.status == "pending"

    connection.status == "mfa_pending" && ImportConnections::Linking.new(connection).verifying?
  end

  def import_connection_badge(connection, enabled:)
    state = import_connection_state(connection, enabled:)
    tag.span(t("settings.connections.states.#{state}"), class: "badge #{STATE_STYLES.fetch(state)}")
  end

  # Whether the account has a connected-services area at all: the operator
  # enables a source, or the account still holds a connection to one the
  # operator has since disabled, which it must still be able to unlink
  # (DESIGN.md §8.6). The account menu reads it.
  def connections_available?
    return @connections_available unless @connections_available.nil?

    @connections_available =
      Allure::RemoteImports::Config.any_enabled? ||
      (current_user.present? && current_user.import_connections.where.not(status: "unlinked").exists?)
  end

  # The hub's rows (DESIGN.md §8.6): one per service the account may see, with
  # its state and, once linked, the account it reads and when it last synced.
  def connections_hub_groups(cards)
    [ { key: :sources, title: t("settings.connections.nav.group"),
        empty: t("settings.connections.none_enabled"),
        items: cards.map { |card| connections_hub_item(card) } } ]
  end

  # A service's page navigation: the same list, text only, as the settings
  # shell's own navigation (DESIGN.md §8.5).
  def connections_navigation_groups(cards:, active:)
    [ { key: :sources, title: t("settings.connections.nav.group"),
        items: cards.map { |card|
          source = card[:source]
          { label: t("workouts.batch_import.sources.#{source.key}.label"),
            path: connection_path(source.key),
            active: source.key == active }
        } } ]
  end

  private

  def connections_hub_item(card)
    source = card[:source]
    connection = card[:connection]
    { label: t("workouts.batch_import.sources.#{source.key}.label"),
      path: connection_path(source.key),
      icon_html: import_source_icon_tag(source),
      detail: connections_hub_detail(connection),
      badge: import_connection_badge(connection, enabled: card[:enabled]) }
  end

  def connections_hub_detail(connection)
    return if connection.disconnected? || connection.external_account_name.blank?

    if connection.last_synced_at
      t("settings.connections.hub.linked_detail",
        account: connection.external_account_name,
        time: time_ago_in_words(connection.last_synced_at))
    else
      t("settings.connections.hub.linked_never", account: connection.external_account_name)
    end
  end
end
