# frozen_string_literal: true

module SettingsHelper
  # The settings collection shared by the universal /settings hub and the
  # sub-page shell (DESIGN.md §8.5). `controller_path` marks the active entry on
  # a sub-page; the hub passes none. Feature-gated entries stay gated here so
  # both surfaces render the same collection (the iOS companion never lists
  # the API page).
  def settings_navigation_groups(controller_path: nil)
    account_items = [
      { label: t("settings.hub.profile.title"), path: settings_profile_path, icon: "user",
        active: controller_path == "settings/profiles" },
      { label: t("navigation.appearance"), path: settings_appearance_path, icon: "palette",
        active: controller_path == "settings/appearance" },
      { label: t("navigation.units"), path: settings_units_path, icon: "ruler",
        active: controller_path == "settings/units" },
      { label: t("settings.sports.title"), path: settings_sports_path, icon: "activity",
        active: controller_path == "settings/sports" },
      { label: t("settings.heart_rate.title"), path: settings_heart_rate_path, icon: "heart-rate-monitor",
        active: controller_path == "settings/heart_rate" }
    ]

    publishing_items = [
      { label: t("settings.hub.publishing_profiles.title"), path: publishing_profiles_path, icon: "share-2",
        active: controller_path == "publishing_profiles" },
      { label: t("settings.hub.privacy_zones.title"), path: privacy_zones_path, icon: "shield-lock",
        active: controller_path == "privacy_zones" }
    ]

    system_items = [
      { label: t("settings.hub.notifications.title"), path: settings_notifications_path, icon: "bell",
        active: controller_path == "settings/notifications" },
      { label: t("settings.data.title"), path: settings_data_path, icon: "database",
        active: controller_path == "settings/data" }
    ]
    system_items << { label: t("settings.elevation.title"), path: settings_elevation_path, icon: "mountain",
                       active: controller_path == "settings/elevation" } if Allure::Elevation::Config.configured?
    system_items << { label: t("settings.weather.title"), path: settings_weather_path, icon: "cloud",
                       active: controller_path == "settings/weather" } if Allure::Weather::Config.enabled?
    system_items << { label: t("settings.assistant.title"), path: settings_assistant_path, icon: "sparkles",
                       active: controller_path == "settings/assistant" } if Allure::Assistant::Config.enabled?
    system_items << { label: t("settings.api.title"), path: settings_api_path, icon: "code",
                       active: controller_path.in?(%w[settings/api settings/api_tokens settings/webhooks]) } unless hotwire_native_app?
    system_items << { label: t("settings.hub.security.title"), path: settings_security_path, icon: "shield",
                       active: controller_path == "settings/security" }
    system_items << { label: t("settings.account.title"), path: settings_account_path, icon: "user-cog",
                       active: controller_path == "settings/account" }

    [
      { key: :account, title: t("settings.nav.groups.account"), items: account_items },
      { key: :publishing, title: t("settings.nav.groups.publishing"), items: publishing_items },
      { key: :system, title: t("settings.nav.groups.system"), items: system_items }
    ]
  end

  # One sortable table header (DESIGN.md §10.5): the label links to the same
  # page sorted by this column, first ascending then toggling; the cell carries
  # `aria-sort` and the active column shows its direction. `current_sort` is the
  # `field_direction` URL value the page was rendered with, and `route` is the
  # route helper that rebuilds the page URL with the next sort.
  def settings_sort_header(label, field, route:, current_sort:, cell_class: nil)
    field = field.to_s
    prefix = "#{field}_"
    direction = current_sort.to_s.start_with?(prefix) ? current_sort.to_s.delete_prefix(prefix) : nil
    next_direction = direction == "asc" ? "desc" : "asc"
    state = { "asc" => "ascending", "desc" => "descending" }.fetch(direction, "none")
    icon = { "asc" => "ti-sort-ascending", "desc" => "ti-sort-descending" }.fetch(direction, "ti-arrows-sort")

    tag.th(scope: "col", "aria-sort": state, class: class_names("allure-sort-cell", cell_class)) do
      link_to public_send(route, sort: "#{field}_#{next_direction}"),
            class: class_names("allure-sort-link", "allure-sort-link--active" => direction.present?),
            aria: { label: t("settings.table.sort_by", column: label) } do
        safe_join([ label, tag.i("", class: class_names("ti", icon, "ms-1"), aria: { hidden: true }) ], " ")
      end
    end
  end

  # Time-zone choices as `[label, IANA identifier]` pairs. Rails' own zone
  # names are labels only: the stored value is the IANA identifier the model
  # validates and PostgreSQL reads. Rails zones sharing one identifier keep
  # their first label, and a stored identifier Rails does not list is kept at
  # the top so saving the form never changes it silently.
  def time_zone_options_for(selected)
    options = ActiveSupport::TimeZone.all.uniq { |zone| zone.tzinfo.identifier }
                                     .map { |zone| [ zone.to_s, zone.tzinfo.identifier ] }
    return options unless User::TIME_ZONE_IDENTIFIERS.include?(selected)
    return options if options.any? { |_label, value| value == selected }

    [ [ selected, selected ], *options ]
  end
end
