# frozen_string_literal: true

module SegmentsHelper
  # The leaderboard's pace/speed column follows the sport's preferred display:
  # speed sports read `Vitesse`, pace sports `Allure`, and a sport that shows
  # both labels the column accordingly (docs/dev/SEGMENTS.md).
  def leaderboard_pace_speed_header(sport)
    key = {
      "speed" => :speed,
      "pace_and_speed" => :pace_speed
    }.fetch(sport&.pace_speed_display, :pace)
    t("segments.leaderboard.#{key}")
  end

  # Display rows for a leaderboard (docs/dev/SEGMENTS.md). The viewer reads
  # their own name, the names of the accounts they follow, and every name on a
  # course they created (linked to profiles); everyone else reads a stable
  # per-segment alias with the date coarsened to the month. Anonymous rows
  # always keep their alias. Collisions resolve deterministically within the
  # board.
  def shared_leaderboard_rows(efforts, segment, owner_view: false)
    used_aliases = []
    efforts.map do |effort|
      if pseudonymous_effort?(effort, segment, owner_view)
        name = Allure::Leaderboard::Alias.resolve(
          user_id: effort.user_id,
          segment_id: segment.id,
          existing: used_aliases,
          locale: I18n.locale
        )
        used_aliases << name
        { effort:, athlete: name, linked: false, date: format_month_year(effort.started_at) }
      else
        { effort:, athlete: effort.user.display_name, linked: true, date: format_started_at(effort.started_at) }
      end
    end
  end

  SPARKLINE_WIDTH = 96
  SPARKLINE_HEIGHT = 28
  THUMBNAIL_SIZE = 40

  # A sortable header of the segment index (DESIGN.md §10.5): the header
  # writes the same `sort` value as the toolbar's sort select.
  def segment_sort_header(label, field, align: nil, extra_classes: nil)
    current = list_query.sort == field ? list_query.direction : nil
    # A first click sorts the newest first, everything else smallest first.
    next_direction = if current
      current == "asc" ? "desc" : "asc"
    else
      field == "created" ? "desc" : "asc"
    end
    state = { "asc" => "ascending", "desc" => "descending" }.fetch(current, "none")
    icon = { "asc" => "ti-sort-ascending", "desc" => "ti-sort-descending" }.fetch(current, "ti-arrows-sort")

    tag.th(scope: "col", "aria-sort": state,
           class: class_names("allure-sort-cell", extra_classes, "text-end" => align == :end)) do
      link_to segments_path(segment_list_params(sort: "#{field}_#{next_direction}")),
            class: class_names("allure-sort-link", "allure-sort-link--active" => current.present?),
            aria: { label: t("segments.index.table.sort_by", column: label) } do
        safe_join([ label, tag.i("", class: class_names("ti", icon, "ms-1"), aria: { hidden: true }) ], " ")
      end
    end
  end

  # The index URL state: the kind, the sport filter and the sort survive every
  # link; the page never does.
  def segment_list_params(overrides = {})
    {
      kind: (@kind == "segment" ? nil : @kind),
      sports: list_query.sport_ids.presence,
      sort: (list_query.sort_key == Segments::ListQuery::DEFAULT_SORT ? nil : list_query.sort_key)
    }.merge(overrides).compact
  end

  # An all-sports course reads one row per sport in the index, named like its
  # board sections: `Nom du segment (Sport)` (DESIGN.md §20.6, §20.7).
  def segment_row_title(segment, sport)
    return segment.name if segment.sport_id || sport.nil?

    t("segments.leaderboard.sport_title", name: segment.name, sport: sport_display_name(sport))
  end

  def segment_grade_label(segment)
    return "—" if segment.average_grade.nil?

    t("units.grade.percent", count: format_decimal(segment.average_grade, precision: 1))
  end

  # A course leads with the elevation it is mostly about: its descent when it
  # loses more than it gains, otherwise its ascent.
  def segment_elevation_lead(segment)
    segment.descent.to_f > segment.ascent.to_f ? :descent : :ascent
  end

  # An effort on a reusable segment reads the course's own ascent or descent,
  # one reference profile for every athlete whatever their device recorded.
  # Loops and routes keep the effort's: their laps add up to the workout's
  # own totals.
  def segment_effort_elevation(effort, key)
    segment = effort.segment
    value = segment.kind == "segment" ? segment.public_send(key) : nil
    value.nil? ? effort.public_send(key) : value
  end

  # The index's single elevation cell: the leading figure behind its arrow,
  # named for assistive technology. Nil when the course has no elevation.
  def segment_elevation_label(segment)
    lead = segment_elevation_lead(segment)
    value = segment.public_send(lead)
    return if value.nil?

    safe_join([
      tag.i("", class: class_names("ti", lead == :descent ? "ti-trending-down" : "ti-trending-up"),
                aria: { hidden: true }),
      tag.span(t("segments.index.table.#{lead}_label"), class: "visually-hidden"),
      format_elevation(value)
    ], " ")
  end

  # The course's mini elevation profile (DESIGN.md §20.6), drawn server-side
  # from the stored profile. Nil when the course has none (a course received
  # from another instance, or one built without elevation).
  def segment_sparkline_tag(segment)
    sparkline = Allure::Segments::Sparkline.new(
      segment.elevation_profile, width: SPARKLINE_WIDTH, height: SPARKLINE_HEIGHT
    ).call
    return nil unless sparkline

    label = t("segments.index.table.profile_label",
              min: format_elevation(sparkline.min_elevation), max: format_elevation(sparkline.max_elevation))
    tag.svg(class: "allure-segment-sparkline", viewBox: "0 0 #{SPARKLINE_WIDTH} #{SPARKLINE_HEIGHT}",
            width: SPARKLINE_WIDTH, height: SPARKLINE_HEIGHT, role: "img", aria: { label: },
            preserveAspectRatio: "none") do
      tag.title(label) +
        tag.path(d: sparkline.area, class: "allure-segment-sparkline__area") +
        tag.path(d: sparkline.line, class: "allure-segment-sparkline__line")
    end
  end

  # The course glyph (DESIGN.md §20.6): the simplified line the list query
  # selected as `thumbnail_geojson`, fitted into a square. Decorative: the
  # course name carries the link and the label.
  def segment_thumbnail_tag(segment)
    geojson = segment.attributes["thumbnail_geojson"]
    coordinates = geojson.present? ? JSON.parse(geojson)["coordinates"] : nil
    path = Allure::Segments::Thumbnail.new(coordinates, size: THUMBNAIL_SIZE).call
    content = path ? tag.path(d: path) : nil

    tag.svg(content, class: "allure-segment-thumbnail", viewBox: "0 0 #{THUMBNAIL_SIZE} #{THUMBNAIL_SIZE}",
                     width: THUMBNAIL_SIZE, height: THUMBNAIL_SIZE, aria: { hidden: true }, focusable: "false")
  rescue JSON::ParserError
    nil
  end

  # Display rows for an index podium. The top three go through the same
  # alias rules as the board, in board order, so the names match the
  # leaderboard's first rows exactly; a podium never carries avatars, dates or
  # identifiers (DESIGN.md §19.5).
  def podium_rows(podium, segment, owner_view: false)
    used_aliases = []
    podium.top.each_with_index.map do |effort, index|
      athlete = if pseudonymous_effort?(effort, segment, owner_view)
        Allure::Leaderboard::Alias.resolve(
          user_id: effort.user_id,
          segment_id: segment.id,
          existing: used_aliases,
          locale: I18n.locale
        ).tap { used_aliases << it }
      else
        effort.user.display_name
      end
      { position: index + 1, athlete:, effort: }
    end
  end

  def format_month_year(time)
    return "—" if time.nil?

    zone = current_user&.time_zone || Time.zone
    I18n.l(time.in_time_zone(zone).to_date, format: :month_year)
  rescue StandardError
    I18n.l(time.to_date, format: :month_year)
  end

  # The segment detail card's summary tiles (DESIGN.md §20.6): Distance and
  # the leading elevation (descent on a course that mostly descends) lead for
  # every viewer; a signed-in viewer adds their efforts and, on
  # a shared course, their standing; a private course replaces the standing with
  # participants — on a shared course, the athletes this viewer sees ranked.
  # Values are pre-formatted strings, and `has_unit` lets the shared tile split
  # the unit into a quieter suffix.
  def segment_detail_tiles(segment, efforts:, owner_view:, standing:, signed_in:, participants_count:)
    distance = { key: :distance, label: t("segments.details.distance"), value: format_distance(segment.distance), has_unit: true }
    ascent = { key: :ascent, label: t("segments.details.ascent"), value: format_elevation(segment.ascent), has_unit: true }
    descent = { key: :descent, label: t("segments.details.descent"), value: format_elevation(segment.descent), has_unit: true }
    participants = { key: :participants, label: t("segments.details.participants"), value: participants_count, has_unit: false }
    grade = {
      key: :grade,
      label: t("segments.details.grade"),
      value: segment.average_grade ? t("units.grade.percent", count: format_decimal(segment.average_grade, precision: 1)) : "—",
      has_unit: true
    }
    tolerance = { key: :tolerance, label: t("segments.details.tolerance"), value: format_distance(segment.match_tolerance_meters), has_unit: true }

    lead, other = segment_elevation_lead(segment) == :descent ? [ descent, ascent ] : [ ascent, descent ]
    primary = [ distance, lead ]
    if signed_in
      primary << { key: :efforts, label: t("segments.details.efforts"), value: efforts.size, has_unit: false }
      if segment.shareable?
        primary << ranking_tile(t("segments.details.ranking"), efforts, standing)
      else
        primary << participants
      end
    else
      primary << other << participants
    end

    primary_keys = primary.map { |tile| tile[:key] }
    secondary = []
    secondary << other unless primary_keys.include?(other[:key])
    secondary << grade
    secondary << tolerance if owner_view
    secondary << participants unless primary_keys.include?(:participants)

    { primary:, secondary: }
  end

  # One sport's progression chart payload (docs/dev/SEGMENTS.md): the viewer's
  # own efforts oldest first, each with its personal place (the trophy drawn
  # beside its point), and the trend. Labels are formatted here, so the tooltip
  # reads like the efforts table.
  def segment_progress_payload(line)
    {
      points: line.entries.map { |entry| segment_progress_point(entry) },
      **segment_progress_trend(line.trend)
    }
  end

  # The trend as two aligned series, solid and dotted, each null where the
  # other is drawn; a point bordering both stretches belongs to both, so the
  # line stays continuous.
  def segment_progress_trend(trend)
    solid = []
    dotted = []
    trend.each_with_index do |point, index|
      before = index.positive? ? trend[index - 1].reliable : nil
      after = index < trend.size - 1 ? point.reliable : nil
      x = segment_progress_x(point.started_at)
      y = point.elapsed_time.round(1)
      solid << { x:, y: before == true || after == true ? y : nil }
      dotted << { x:, y: before == false || after == false ? y : nil }
    end
    {
      trend: solid.any? { it[:y] } ? solid : [],
      trend_uncertain: dotted.any? { it[:y] } ? dotted : []
    }
  end

  def segment_progress_gap(entry)
    return t("segments.progress.record") if entry.gap_to_best.zero?

    t("segments.progress.gap", time: format_duration(entry.gap_to_best))
  end

  private

  def segment_progress_point(entry)
    effort = entry.effort
    primary, = pace_speed_values(average_pace: effort.average_pace, average_speed: effort.average_speed, sport: effort.sport)
    place_label = { 2 => t("segments.progress.places.second"), 3 => t("segments.progress.places.third") }[entry.place]
    {
      x: segment_progress_x(effort.started_at),
      y: effort.elapsed_time,
      title: workout_display_title(effort.workout),
      date: format_started_at(effort.started_at),
      time: format_duration(effort.elapsed_time),
      pace: primary,
      gap: [ place_label, segment_progress_gap(entry) ].compact.join(" · "),
      place: entry.place,
      url: workout_path(effort.workout)
    }.compact
  end

  def segment_progress_x(time)
    (time.to_f * 1000).round
  end

  def ranking_tile(label, efforts, standing)
    value, stamp = if standing
      [ t("segments.card.rank", rank: standing[:rank], total: standing[:total]), rank_stamp(standing[:rank]) ]
    elsif efforts.any?
      [ t("segments.listing.unranked"), nil ]
    else
      [ "—", nil ]
    end

    caption = if standing&.dig(:category_rank)
      t("segments.details.category_rank", rank: standing[:category_rank], total: standing[:category_total],
                                          category: t("segments.leaderboard.categories.#{standing[:category]}"))
    end

    { key: :ranking, label:, value:, has_unit: false, stamp:, caption: }.compact
  end

  # The athlete's own anonymity flag always wins; otherwise a name shows to
  # the course creator, to the athlete, and to their followers
  # (docs/dev/SEGMENTS.md).
  def pseudonymous_effort?(effort, _segment, owner_view)
    return true if effort.anonymous?
    return false if owner_view || effort.user_id == current_user&.id

    !segment_followed_user_ids.include?(effort.user_id)
  end

  def segment_followed_user_ids
    @segment_followed_user_ids ||= Segments::Listing.following_user_ids(current_user).to_set
  end

  # The board view switch (DESIGN.md §20.7): every athlete the viewer sees,
  # or only the accounts they follow. Plain GET links, so back and forward
  # work; `path` builds the URL for a `board` value.
  def segment_board_scope_nav(current, &path)
    tag.nav(class: "nav nav-segmented nav-sm", aria: { label: t("segments.leaderboard.scopes.label") }) do
      safe_join(Segments::Listing::SCOPES.map do |scope|
        link_to t("segments.leaderboard.scopes.#{scope}"), path.call(scope == "everyone" ? nil : scope),
                class: class_names("nav-link", active: scope == current),
                aria: { current: (scope == current ? "true" : nil) }
      end)
    end
  end

  # The category view switch (docs/dev/SEGMENTS.md): « Tous » plus each
  # category the board offers. Plain GET links; `path` builds the URL for a
  # `category` value (nil for every athlete).
  def segment_board_category_nav(current, offered, &path)
    choices = [ nil, *offered ]
    tag.nav(class: "nav nav-segmented nav-sm", aria: { label: t("segments.leaderboard.categories.label") }) do
      safe_join(choices.map do |category|
        link_to t("segments.leaderboard.categories.#{category || 'all'}"), path.call(category),
                class: class_names("nav-link", active: category == current),
                aria: { current: (category == current ? "true" : nil) }
      end)
    end
  end

  # The two reaches that name a publication state. Every other reason the
  # board lists nobody — opted out, a zone on the corridor, a publication
  # without the route, a recording credited from another account — reads as the
  # badge's "not published" state, grey under the cut mark; the sentence under
  # the badge says which.
  REACH_PUBLICATION_STATES = { "public" => "public", "followers" => "followers" }.freeze

  # The viewer's own line on a board (DESIGN.md §20.6): who sees them, or the
  # one reason nobody does, in the same badge as every other sharing state —
  # green under the publication mark when the whole instance reads the passage,
  # blue when only their followers do. Nil when they have no effort on the
  # course.
  def segment_reach_badge(reach)
    return nil if reach.nil?

    publication_badge(
      REACH_PUBLICATION_STATES.fetch(reach.to_s, "unpublished"),
      label: t("segments.listing.reach.#{reach}")
    )
  end
end
