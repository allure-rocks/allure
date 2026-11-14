# frozen_string_literal: true

# Renders the tree declared in config/navigation.rb.
#
# Two things are handled here rather than in JavaScript:
#
#   * Visibility. An item whose `policy` the current request fails is never
#     emitted, so it cannot be discovered by reading the HTML.
#   * Active state. Themes usually match `link.href === location.href` in JS,
#     which misses query strings, breaks under Turbo, and flickers. Comparing
#     paths server-side is exact and free.
module NavigationHelper
  def nav_sections(position: :top)
    Allure::Navigation.sections(position:).filter_map do |section|
      items = visible_nav_items(section.items)
      next if items.empty?

      Allure::Navigation::Section.new(key: section.key, position: section.position, items:)
    end
  end

  def nav_item_path(item)
    case item.path
    when Symbol then (respond_to?(item.path) ? public_send(item.path) : nil)
    when Proc   then instance_exec(&item.path)
    else item.path
    end
  end

  # An item is active when it is the current page; a parent is active when any
  # descendant is. Compared on path only, so `?page=2` still highlights.
  def nav_item_active?(item)
    return true if item.leaf? && nav_current?(nav_item_path(item))

    item.items.any? { nav_item_active?(it) }
  end

  def nav_item_label(item) = t("navigation.#{item.key}")

  # The iOS companion draws the topbar in its native bar (DESIGN.md §7.7). Every
  # id names the hidden web control, tagged `data-bridge-item`, that the app
  # asks the bridge to click, so links and forms keep their Turbo behaviour.
  # An entry's path marks a section: opening one replaces the app's history.
  def native_topbar_payload
    {
      menu: {
        label: t("navigation.toggle"),
        sections: nav_sections.map do |section|
          { title: t("navigation.sections.#{section.key}"), items: section.items.map { native_nav_entry(it) } }
        end
      },
      account: { label: t("navigation.account_menu"), title: current_user.display_name,
                 sections: native_account_sections },
      notifications: {
        id: "notifications", title: t("notifications.bell.label"),
        label: notification_bell_label(unread_notifications_count), unread: unread_notifications_count.positive?,
        count: unread_notifications_count
      },
      import: { id: "import", label: t("navigation.import") }
    }
  end

  def nav_bridge_id(item) = "nav-#{item.key}"

  # The companion draws the phone bottom bar as native tabs, one history per
  # tab, and loads each destination itself (DESIGN.md §7.7). An older companion
  # ignores the payload and keeps the web bar.
  def native_tabs_payload
    { tabs: bottom_bar_items.map { |item|
        { id: "tab-#{item[:key]}", title: t("navigation.#{item[:key]}"),
          icon: item[:icon], path: item[:path], active: item[:active] }
      } }
  end

  # Phone bottom bar (DESIGN.md §7.3): Publications / Moi / Activités /
  # Segments / Personnes. Import is a topbar action, not a destination, so it
  # stays out.
  def bottom_bar_items
    [
      { key: :feed, icon: "world", path: feed_path, active: nav_prefix?(feed_path) },
      { key: :me, icon: "user", path: me_path, active: nav_prefix?(me_path) },
      { key: :workouts, icon: "activity", path: workouts_path, active: nav_prefix?(workouts_path) },
      { key: :segments, icon: "route", path: segments_path, active: nav_prefix?(segments_path) },
      { key: :people, icon: "users", path: people_path, active: nav_prefix?(people_path) }
    ]
  end

  private

  def native_nav_entry(item)
    entry = { id: nav_bridge_id(item), title: nav_item_label(item), icon: item.icon, active: nav_item_active?(item) }
    if item.leaf?
      entry[:path] = nav_item_path(item)
    else
      entry[:items] = item.items.map { native_nav_entry(it) }
    end
    entry
  end

  # The same entries as the web account menu, plus the companion's server
  # chooser; the app lists them in its menu after the navigation. Icons are
  # Tabler names the app maps to its own symbols. Connected services join the
  # list only when the account has an area to open (DESIGN.md §8.6).
  def native_account_sections
    [
      [ { id: "profile", title: t("navigation.profile"), icon: "user", path: profile_path(current_user.username) },
        { id: "settings", title: t("navigation.settings"), icon: "settings", path: settings_path },
        ({ id: "connections", title: t("navigation.connections"), icon: "plug-connected", path: connections_path } if connections_available?),
        { id: "help", title: t("navigation.help"), icon: "help-circle", path: help_path },
        { id: "about", title: t("navigation.about"), icon: "info-circle" } ].compact,
      ([ { id: "administration", title: t("navigation.administration"), icon: "shield-lock",
           path: admin_root_path } ] if instance_operator?),
      [ { id: "server", title: t("navigation.server"), icon: "server" } ],
      [ { id: "sign_out", title: t("navigation.sign_out"), icon: "logout", destructive: true } ]
    ].compact.map { { items: it } }
  end

  def visible_nav_items(items)
    items.filter_map do |item|
      next unless nav_item_permitted?(item)

      children = visible_nav_items(item.items)

      # A parent whose children are all hidden, and which has no route of its
      # own, would render as a dead expander.
      next if !item.leaf? && children.empty?

      # Skip anything pointing at a route helper that does not exist yet. This
      # lets navigation.rb describe the finished application while the routes
      # are still being built out, without 500ing every page in the meantime.
      next if item.leaf? && nav_item_path(item).nil?

      Allure::Navigation::Item.new(
        key: item.key, icon: item.icon, path: item.path,
        policy: item.policy, items: children
      )
    end
  end

  def nav_item_permitted?(item)
    return true if item.policy.nil?

    respond_to?(item.policy, true) && public_send(item.policy)
  end

  def nav_current?(path)
    return false if path.blank?

    current = request.path
    current == path || (path != "/" && current.start_with?("#{path}/"))
  end

  def nav_prefix?(path) = nav_current?(path)
end
