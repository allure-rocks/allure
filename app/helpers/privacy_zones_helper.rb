# frozen_string_literal: true

module PrivacyZonesHelper
  def zone_search_messages
    {
      searching: t("privacy_zones.form.search.searching"),
      empty: t("privacy_zones.form.search.empty"),
      too_short: t("privacy_zones.form.search.too_short"),
      unavailable: t("privacy_zones.form.search.unavailable"),
      selected: t("privacy_zones.form.search.selected", label: "%{label}")
    }
  end
end
