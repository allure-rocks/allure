# frozen_string_literal: true

module ApplicationHelper
  FLASH_CSS = {
    "notice" => "success",
    "success" => "success",
    "alert" => "danger",
    "error" => "danger",
    "warning" => "warning",
    "info" => "info"
  }.freeze

  # The iOS companion's server chooser (DESIGN.md §7.7). The app intercepts
  # this same-origin path before any request; Rails has no route for it.
  NATIVE_SERVER_PATH = "/native/server"

  def flash_css_class(type) = FLASH_CSS.fetch(type.to_s, "info")

  # Avatar component (DESIGN.md §9.5), sizes xs–xl. A person's avatar is a
  # circle: Tabler's default `.avatar` already carries the pill radius, so no
  # shape class is added — `avatar-square` is reserved for non-person marks.
  # The chain resolves server-side: uploaded image, proxied Gravatar when opted
  # in and cached, generated pink geometry otherwise. Never the only
  # identifier: adjacent text names the account, so decorative defaults to
  # hiding it from assistive tech.
  AVATAR_SIZES = %w[xs sm md lg xl].freeze

  def avatar_tag(user, size: "md", decorative: true)
    size = AVATAR_SIZES.include?(size.to_s) ? size.to_s : "md"
    classes = "avatar avatar-#{size}"
    supporter_badge = user.funding_badge_visible?
    operator_badge = user.instance_operator? && !user.deactivated?
    labels = [ user.display_name ]
    labels << t("operator.badge.label") if operator_badge
    labels << t("funding.badge.label") if supporter_badge
    label = labels.join(" — ")
    avatar = if user.avatar_image?
      image_tag profile_avatar_path(user.username), class: classes, alt: (decorative ? "" : label)
    else
      render "shared/generated_avatar", seed: user.avatar_seed, classes: classes,
        label: (decorative ? nil : label)
    end
    return avatar unless supporter_badge || operator_badge

    badges = []
    if operator_badge
      badges << tag.span(tag.i(class: "ti ti-user-shield", aria: { hidden: true }),
                         class: "operator-badge", aria: { hidden: true })
    end
    if supporter_badge
      color = user.funding_badge_color.presence_in(Allure::Funding::BADGE_COLORS) || "primary"
      icon = tag.i(class: "ti #{ReactionsHelper::ICONS.fetch(user.funding_badge_tier)}", aria: { hidden: true })
      badges << tag.span(icon, class: "funding-badge funding-badge--#{color}", aria: { hidden: true })
    end
    tag.span class: "avatar avatar-#{size} avatar-badged" do
      safe_join([ avatar, *badges ])
    end
  end

  def funding_available? = signed_in? && Allure::Funding.enabled? && !hotwire_native_app?

  def funding_admin_available? = instance_operator? && funding_available?

  # The same avatar component for an actor (DESIGN.md §9.5, §24). A local actor
  # is its account's public face, so it renders the account's chain (uploaded
  # image, cached Gravatar, persisted seed): the People list, notifications and
  # the feed must show the same avatar. A remote actor renders the cached copy
  # served by this instance, or generated geometry seeded by the actor URI.
  def actor_avatar_tag(actor, size: "md", decorative: true)
    return avatar_tag(actor.user, size:, decorative:) if actor.local? && actor.user

    size = AVATAR_SIZES.include?(size.to_s) ? size.to_s : "md"
    classes = "avatar avatar-#{size}"
    label = actor_name(actor)
    if actor.avatar_cached?
      image_tag remote_profile_avatar_path(actor.acct.presence || actor.handle),
                class: classes, alt: (decorative ? "" : label)
    else
      render "shared/generated_avatar", seed: Zlib.crc32(actor.uri.to_s), classes: classes,
        label: (decorative ? nil : label)
    end
  end

  # The single Bootstrap tooltip the repository uses for every tooltip: it
  # follows hover, keyboard focus and touch (DESIGN.md §10.3, §10.17), where a
  # native `title` does not, and it never returns as a `title` attribute the
  # way Tabler's own `dispose` restores one. `media` gates it on a media query:
  # an element that prints its own label from a wider width up only needs the
  # tooltip — and a focus stop — below it.
  def tooltip_data(label, media: nil)
    data = { controller: "tooltip", bs_toggle: "tooltip", bs_title: label }
    data[:tooltip_media_value] = media if media.present?
    data
  end

  def actor_name(actor) = actor.display_name.presence || actor.handle.presence || actor.uri

  def actor_handle(actor) = "@#{actor.acct.presence || actor.handle.presence || actor.uri}"

  # A tombstoned actor keeps its row to answer 410 and to deliver its
  # withdrawal; everywhere a name or handle would show, it renders as a
  # deleted account instead (the avatar already falls back to generated art).
  def actor_deleted?(actor) = actor.nil? || actor.tombstoned?

  def actor_profile_path(actor)
    return profile_path(actor.user.username) if actor.local? && actor.user

    remote_profile_path(actor.acct.presence || actor.handle)
  end

  # Sport identity mark (DESIGN.md §6.5). Sport has no per-sport colour: every
  # tile carries the same brand-primary tint and the per-sport SVG carries the
  # identity. The tile is Tabler's avatar component in its `avatar-square`
  # shape (sizes and glyph tokens come from Tabler); `sport-tile` only adds the
  # brand tint. Beside a printed sport name the tile is decorative; with a
  # `label` it becomes the accessible, tooltipped mark (used on workout cards,
  # where the printed name is gone), and with an `href` it also links out —
  # sitting above a linked card's stretched link.
  def sport_icon_tag(sport)
    render(sport.icon)
  end

  SPORT_TILE_SIZES = %w[md lg sm xs].freeze

  def sport_tile_tag(sport, size: :md, label: nil, href: nil)
    size = SPORT_TILE_SIZES.include?(size.to_s) ? size.to_s : "md"
    attributes = {
      class: class_names(
        "avatar", "avatar-square", "avatar-#{size}", "sport-tile",
        "sport-tile--link" => href.present?
      )
    }
    if label
      attributes[:role] = "img" if href.blank?
      attributes[:aria] = { label: }
      attributes[:data] = tooltip_data(label)
    else
      attributes[:aria] = { hidden: true }
    end

    content = sport_icon_tag(sport)
    href ? link_to(content, href, **attributes) : tag.span(content, **attributes)
  end

  # The same sport SVG inside a segmented control (DESIGN.md §10.15): the
  # control's own `nav-link-icon` token sizes it, so a tile with its own
  # background and border never overflows the control's inner height. The
  # icon-only segment keeps its name on the surrounding link.
  def sport_switch_icon_tag(sport)
    tag.span(render(sport.icon), class: "nav-link-icon", aria: { hidden: true })
  end

  # The iOS companion (DESIGN.md §7.7) falls back to the document title in its
  # native bar outside the tab sections, so it gets the page name alone,
  # without the application suffix.
  def page_title
    base = t("app.name")
    return base unless content_for?(:title)

    hotwire_native_app? ? content_for(:title) : safe_join([ content_for(:title), " · ", base ])
  end

  # Hotwire Native puts this marker in the companion's user agent. It only
  # trims duplicated chrome (DESIGN.md §7.7); it never grants or hides data.
  def hotwire_native_app?
    request.user_agent.to_s.include?("Hotwire Native")
  end

  # Data attributes of a form on an auth-layout page. In a browser the form
  # submits natively: password managers watch the <body> they found at load
  # and never see a page Turbo swapped in, so the layout also forces a full
  # load (`turbo-visit-control`). The companion keeps Turbo and its keychain.
  def credential_form_data(**data)
    hotwire_native_app? ? data : data.merge(turbo: false)
  end

  # The bridge components the companion registered, which it lists in the same
  # user agent. Rails reads it to render the web counterpart up front, without
  # waiting for the bridge to connect.
  def hotwire_native_bridge?(component)
    registered = request.user_agent.to_s[/bridge-components: \[([^\]]*)\]/, 1]
    registered.to_s.split.include?(component.to_s)
  end

  # Rendered into <html data-bs-theme>, so the correct theme is present on the
  # very first paint. Doing this server-side is what avoids the flash of light
  # theme that every JS-only implementation suffers from. The iOS companion's
  # own Appearance setting arrives in a cookie browsers never carry
  # (DESIGN.md §7.7) and wins for its requests; the account theme governs the
  # web on its own.
  def current_theme
    if hotwire_native_app?
      companion = request.cookies["allure_companion_theme"]
      return companion if User::THEMES.include?(companion)
    end
    theme = current_user&.theme
    User::THEMES.include?(theme) ? theme : "light"
  end

  # Footer version line and its what's-new dialog (DESIGN.md §10.9). Notes are
  # curated per release in config/release_notes.yml; the dialog trigger only
  # exists when the running release has notes to show, so a quiet release
  # leaves the footer a plain version rather than a dead button.
  def current_release_notes
    return @current_release_notes if defined?(@current_release_notes)

    @current_release_notes = Allure::ReleaseNotes.for(version: Allure::VERSION, locale: I18n.locale)
  end

  def release_notes_unseen?
    signed_in? && current_release_notes.present? &&
      current_user.release_notes_seen_version != Allure::VERSION
  end

  # Development only. Vite injects the stylesheet from the JS entrypoint there,
  # so the browser can paint raw HTML while the modules load. Asking the dev
  # server for the compiled CSS directly (`?direct`) renders a render-blocking
  # <link>, exactly like the stylesheet link the production manifest already
  # produces through vite_javascript_tag. The path is relative to Vite's root
  # (sourceCodeDir, app/frontend). Production and test return nil.
  def vite_development_stylesheet_tag
    return unless Rails.env.development? && ViteRuby.instance.dev_server_running?

    tag.link rel: "stylesheet",
             href: "/#{ViteRuby.instance.config.public_output_dir}/styles/application.scss?direct"
  end

  # Both basemap style documents. The map needs both so a theme toggle swaps the
  # basemap without a round trip; it opens on whichever matches the theme the
  # layout has already rendered into data-bs-theme, so there is no flash of the
  # wrong basemap either.
  def map_style_url = Allure::Maps.config.style_url
  def map_dark_style_url = Allure::Maps.config.dark_style_url

  # The account preference « Cartes et images des parcours » (DESIGN.md
  # §15.2, §15.4) governs the live basemap as well as the generated route
  # images: `auto` follows the page theme, `light`/`dark` force one variant.
  # The map element carries the resolved theme as its own `data-bs-theme`, so
  # its controls, markers and popups follow the basemap from the first frame.
  def basemap_theme_preference
    preference = current_user&.route_image_theme
    User::ROUTE_IMAGE_THEMES.include?(preference) ? preference : "auto"
  end

  def basemap_theme
    preference = basemap_theme_preference
    preference == "auto" ? current_theme : preference
  end

  # The world map image drawn under a virtual activity's track instead of the
  # ordinary basemap (docs/dev/VIRTUAL-PLATFORMS.md). The sport decides whether a world may
  # apply at all: Zwift's London sits on London, so geometry alone would claim
  # a real ride there. A world whose image the operator has not generated keeps
  # the ordinary basemap, and the profile's own `basemap: false` wins over
  # everything.
  def virtual_basemap_for(display, basemap: true)
    return nil unless basemap

    sport = display.respond_to?(:sport) ? display.sport : nil
    return nil unless sport.respond_to?(:virtual?) && sport.virtual?

    point = virtual_basemap_point(display)
    return nil unless point

    Allure::Virtual::Platforms.basemap_at(
      longitude: point[0], latitude: point[1], public_root: Rails.public_path
    )
  end

  # The viewer's effective workout-map smoothing level (PLAN_MAPLIBRE.md §9).
  # Course maps hard-code their own medium level; workout maps follow this
  # account preference, and the map options toggle persists it.
  def account_track_smoothing = current_user&.smooth_tracks ? current_user.track_smoothing_level : "off"

  def account_track_smoothing_level = current_user&.track_smoothing_level.presence || "medium"

  # The point that decides which virtual world a page belongs to: a workout has
  # its recorded start, a publication or received note only its sanitized
  # track. Nil when there is no geometry to ask.
  def virtual_basemap_point(display)
    if display.respond_to?(:start_point) && (point = display.start_point)
      [ point.x, point.y ]
    elsif display.respond_to?(:track)
      feature = Array(display.track&.dig("features")).first
      coordinates = feature&.dig("geometry", "coordinates")&.first
      coordinates if coordinates.is_a?(Array) && coordinates.length >= 2
    end
  end

  # One generated route image in the viewer's theme (DESIGN.md §15.4).
  # `auto` (the default) follows the page theme — the same `data-bs-theme` the
  # layout renders and every map and chart follow — so the server paints the
  # matching variant on the first frame, and the `route-image` controller swaps
  # it live when the theme changes, in the browser or in the companion through
  # the shared `allure:theme-changed` event. Both URLs travel as Stimulus value
  # attributes, so the swap needs no round trip. `light`/`dark` force one URL
  # and leave nothing to swap. Callers pass both themed URLs and keep every
  # attribute (alt, classes, dimensions, loading) on the image.
  def route_image_tag(light_url:, dark_url:, **image_options)
    case current_user&.route_image_theme
    when "light"
      image_tag(light_url, **image_options)
    when "dark"
      image_tag(dark_url, **image_options)
    else
      image_tag(
        current_theme == "dark" ? dark_url : light_url,
        **image_options,
        data: {
          controller: "route-image",
          route_image_light_url_value: light_url,
          route_image_dark_url_value: dark_url,
          action: "allure:theme-changed@window->route-image#themeChanged"
        }
      )
    end
  end

  # MapLibre labels its own controls through a `locale` option keyed by its
  # internal identifiers. Handing the whole table over as one JSON value keeps
  # that vocabulary out of the markup, where it would otherwise be a data
  # attribute per string.
  #
  # The scale bar reuses the unit symbols the elevation chart already uses, so
  # the two never disagree about how to abbreviate a kilometre.
  def map_control_locale
    {
      "NavigationControl.ZoomIn" => t("maps.controls.zoom_in"),
      "NavigationControl.ZoomOut" => t("maps.controls.zoom_out"),
      "NavigationControl.ResetBearing" => t("maps.controls.reset_bearing"),
      "FullscreenControl.Enter" => t("maps.controls.enter_fullscreen"),
      "FullscreenControl.Exit" => t("maps.controls.exit_fullscreen"),
      "GeolocateControl.FindMyLocation" => t("maps.controls.find_my_location"),
      "GeolocateControl.LocationNotAvailable" => t("maps.controls.location_not_available"),
      "AttributionControl.ToggleAttribution" => t("maps.controls.toggle_attribution"),
      "CooperativeGesturesHandler.MobileHelpText" => t("maps.controls.two_fingers"),
      "ScaleControl.Meters" => t("units.symbols.metre"),
      "ScaleControl.Kilometers" => t("units.symbols.kilometre"),
      "ScaleControl.Feet" => t("units.symbols.foot"),
      "ScaleControl.Miles" => t("units.symbols.mile")
    }
  end

  # The colour-by legend's labels and units (DESIGN.md §15.2): the metric names
  # the selector already uses, and the unit each ramp end prints in the viewer's
  # own unit system.
  def map_legend_locale
    imperial = current_user&.unit_system == "imperial"
    {
      "elevation" => {
        "label" => t("maps.colour_by.elevation"),
        "unit" => t(imperial ? "units.symbols.foot" : "units.symbols.metre")
      },
      "speed" => {
        "label" => t("maps.colour_by.speed"),
        "unit" => t(imperial ? "units.speed.mph" : "units.speed.kmh")
      },
      "power" => {
        "label" => t("maps.colour_by.power"),
        "unit" => t("units.power.watt")
      }
    }
  end

  def theme_controller_attributes
    attributes = {
      data: {
        controller: "theme",
        theme_current_value: current_theme
      }
    }

    # The persistence endpoint arrives with the settings screens. Until then the
    # controller degrades to localStorage rather than POSTing into the void.
    if signed_in? && respond_to?(:settings_appearance_path)
      attributes[:data][:theme_persist_url_value] = settings_appearance_path
    end

    attributes
  end
end
