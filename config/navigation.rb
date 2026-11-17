# frozen_string_literal: true

# The single source of truth for application navigation.
#
# Tabler (like most admin themes) ships its menu as hand-written nested <ul>
# markup, duplicated once per layout variant. That is unmaintainable and it is
# how themes end up with dead links pointing at routes that no longer exist.
#
# Instead the tree lives here, is rendered by one recursive partial, and its
# active state is computed server-side. Labels are i18n keys, never literals.
#
# Contract (DESIGN.md §8.2):
#   * no leaf points at an unrouted helper — the helper skips such leaves, so
#     an entry here must resolve or it silently vanishes;
#   * no single-child dropdown;
#   * every parent is a landing page — parents render as dropdowns, so the
#     landing page is repeated as the explicit first child (overview);
#   * icons are Tabler names without the `ti-` prefix, distinct within the tree.
#
#   label:   I18n key under `navigation.`
#   icon:    Tabler icon name, without the `ti-` prefix
#   path:    a symbol naming a route helper, or a lambda for dynamic paths
#   policy:  optional symbol; the item is hidden unless the helper answers true
#   items:   child entries, rendered as a collapsible section
Allure::Navigation.define do
  section :main do
    # The personal stream and the instance's public publications share this one
    # destination; the Public switch selects what joins the stream.
    item :feed, icon: "world", path: :feed_path, policy: :signed_in?

    item :me, icon: "user", path: :me_path, policy: :signed_in?
    item :workouts, icon: "activity", path: :workouts_path, policy: :signed_in?
    item :people, icon: "users", path: :people_path, policy: :signed_in?
  end

  section :explore do
    item :segments, icon: "route", path: :segments_path, policy: :signed_in?
    item :equipment, icon: "bike", path: :equipments_path, policy: :signed_in?
  end

  # Operator console (docs/dev/ADMIN.md). Rendered exclusively by the admin layout
  # through `nav_sections(position: :admin)`; the product chrome (top, bottom,
  # account dropdown) never emits it. Leaves whose route does not exist yet are
  # skipped, so this tree may describe the finished console while its slices
  # land. Every item is policy-gated as defense in depth on top of
  # Admin::BaseController's 404.
  section :admin, position: :admin do
    item :admin_dashboard, icon: "gauge", path: :admin_root_path, policy: :instance_operator?
    item :admin_jobs, icon: "stack-2", path: :admin_jobs_path, policy: :instance_operator?
    item :admin_federation, icon: "broadcast", path: :admin_federation_path, policy: :instance_operator?
    item :admin_publications, icon: "world", path: :admin_publications_path, policy: :instance_operator?
    item :admin_accounts, icon: "users", path: :admin_accounts_path, policy: :instance_operator?
    item :admin_funding, icon: "coffee", path: :admin_funding_path, policy: :funding_admin_available?
    item :admin_invitations, icon: "mail", path: :admin_invitations_path, policy: :instance_operator?
    item :admin_imports, icon: "file-import", path: :admin_imports_path, policy: :instance_operator?
    item :admin_system, icon: "server-2", path: :admin_system_path, policy: :instance_operator?
    item :admin_events, icon: "history", path: :admin_events_path, policy: :instance_operator?
  end
end
