# frozen_string_literal: true

class WorkoutsController < ApplicationController
  include Pagy::Method

  before_action :set_workout_for_show, only: :show
  before_action :set_owned_workout, only: %i[edit update destroy publish destroy_publication republish publication_preview delivery_refresh activate_publication reschedule_publication destroy_scheduled_publication destroy_auto_publication]
  # A credit row is read-only except for its deletion (docs/dev/SHARED-ACTIVITIES.md).
  before_action :refuse_credit_row, only: %i[edit update publish destroy_publication republish publication_preview delivery_refresh activate_publication reschedule_publication destroy_scheduled_publication destroy_auto_publication]
  before_action :ensure_publishing_profiles, only: %i[show publish republish publication_preview]
  before_action :set_equipments, only: %i[edit update]

  # The filter vocabulary lives in Workouts::ListQuery, which the bulk
  # selection replays; these aliases keep the views, helpers and specs that
  # name the controller constants working.
  FILTER_PERIODS = Workouts::ListQuery::PERIODS
  FILTER_PUBLICATIONS = Workouts::ListQuery::PUBLICATIONS
  FILTER_COMMUTES = Workouts::ListQuery::COMMUTES
  FILTER_SORTS = Workouts::ListQuery::SORTS
  FILTER_DIRECTIONS = Workouts::ListQuery::DIRECTIONS
  FILTER_SORT_KEYS = Workouts::ListQuery::SORT_KEYS

  helper_method :filter_period, :filter_publication, :filter_commute, :filter_sort, :filter_direction,
                :filter_sort_key, :filter_query, :filter_place

  def index
    @practiced_sports = practiced_sports
    scope = current_user.workouts
      .includes(:sport, :user, :active_publications, :scheduled_publications, :records, :effort_records,
                :credited_by, :credited_from, participant_links: { workout: :user },
                workout_participations: { participant_actor: :user },
                route_image_attachment: :blob)
    @pagy, @workouts = pagy(list_query.resolve(scope:), limit: 20)
    @view = params[:view] == "table" ? "table" : "card"
    @bulk_equipments = bulk_equipments
  end

  def show
    # The participant's own credit row has its own page: the credited metric
    # set and its deletion, nothing drawn from a track (docs/dev/SHARED-ACTIVITIES.md).
    return show_credit if @workout.credit? && @workout.user == current_user
    # A manual entry is its owner's alone and has its own page: the typed
    # figures, nothing drawn from a track (docs/dev/MANUAL-ENTRY.md).
    return render(:manual) if @workout.manual? && @workout.user == current_user

    owner = @workout.user == current_user
    @active_publications = WorkoutPublication.by_precedence(@workout.active_publications.to_a)
    @scheduled_publications = owner ? WorkoutPublication.by_precedence(@workout.scheduled_publications.to_a) : []
    @auto_publications = owner ? @workout.auto_publications.includes(:workout_publication).order(:id).to_a : []
    # A reader is served the narrowest publication they are entitled to
    # (docs/dev/PUBLISHING.md). `?as=publication` lets the owner read the page
    # exactly as a reader of one publication sees it — `audience` names which,
    # the narrowest by default (DESIGN.md §20.3); without one it is ignored.
    @publication = Workouts::PublicationResolver.new(workout: @workout, user: current_user).call unless owner
    if owner && params[:as] == "publication"
      @publication = Workouts::PublicationResolver.new(workout: @workout, user: current_user, audience: params[:audience]).call
      @reader_preview = @publication.present?
    end
    # The reaction bar's batched summary (docs/dev/REACTIONS.md).
    @reaction_targets = [ @workout ]
    @display_workout = if @publication
      Workouts::PublicationView.new(@publication, principal: Workouts::PublicationPrincipal.browser(current_user))
    else
      @workout
    end
    # The owner's assistant summary card (docs/dev/AI.md §7): never for a
    # reader, the owner's reader preview, a manual entry or a credit row.
    @summary_visible = owner && !@reader_preview && Workouts::SummaryEligibility.eligible?(@workout)
    @profiles = current_user&.publishing_profiles&.order(:position, :id) || []
    @publication_readiness = publication_readiness
    @selected_profile = selected_publishing_profile if @workout.user == current_user
    @delivery_summaries = if owner
      @active_publications.to_h { |publication| [ publication.id, Workouts::DeliverySummary.new(publication:).call ] }
    else
      {}
    end
    @segment_efforts = if @workout.user == current_user
      @workout.segment_efforts.includes(:segment).order(:started_at, :segment_id, :occurrence_index)
    else
      []
    end
    # The board rank of each effort's (segment, sport), owner-only, shown as a
    # rank medal beside the gold RP badge. Fail-closed: a private or
    # ineligible segment has no rank and the badge stands alone.
    @segment_ranks = if @segment_efforts.any?
      Segments::Standings.new(segments: @segment_efforts.map(&:segment).uniq, viewer: current_user)
        .call
        .index_by { |row| [ row.segment.id, row.sport.id ] }
    else
      {}
    end
    # Laps, climbs, descents, stops, intervals, and splits are owner-only.
    # Recorded laps keep their own tab; every smart-lap source is a derived row
    # rebuilt with the matching job and is never part of a publication.
    @laps = owner ? @workout.laps : []
    @detected_laps = owner ? @workout.detected_laps.laps.chronological.to_a : []
    @climbs = owner ? @workout.detected_laps.climbs.chronological.to_a : []
    @descents = owner ? @workout.detected_laps.descents.chronological.to_a : []
    @stops = owner ? @workout.detected_laps.stops.chronological.to_a : []
    @intervals = owner ? @workout.detected_laps.efforts.chronological.to_a : []
    @best_efforts = owner ? @workout.best_efforts.order(:duration_seconds).to_a : []
    @effort_records_held = owner ? @workout.effort_records.to_a : []
    # Owner-only personal places (record, second and third best time) of this
    # workout's best efforts and segment efforts, derived on read
    # (DESIGN.md §10.4); never part of a publication.
    @best_effort_places = owner ? best_effort_places : {}
    @segment_effort_places = owner ? Segments::PersonalPlaces.new(user: current_user, efforts: @segment_efforts).call : {}
    @segment_effort_gaps = owner ? Segments::PersonalBestGaps.new(user: current_user, efforts: @segment_efforts).call : {}
    @records_held = owner ? Record.where(user: current_user, workout: @workout).to_a : []
    @max_climb_lap = if owner && @records_held.any? { |record| record.record_type == "MC" }
      @climbs.max_by { |climb| climb.ascent.to_f }
    end
    @splits = if owner
      Workouts::SplitsService.new(workout: @workout, unit: current_user.unit_system).call
    else
      []
    end
    @chart_table = chart_table_points
    @chart_available_series = (Allure::Gpx::ChartSeries::SERIES_KEYS.keys + Workouts::WeatherChartValues::KEYS).select do |key|
      @chart_table.any? { |point| !point[key].nil? }
    end
  end

  def edit
    @sports = Sport.catalog_order
    @has_active_publication = @workout.active_publications.any?
    @manual_form = ManualWorkoutForm.from_workout(@workout, user: current_user) if @workout.manual?
  end

  def update
    return update_manual if @workout.manual?

    @sports = Sport.catalog_order
    @has_active_publication = @workout.active_publications.any?

    if invalid_sport_selection?
      @workout.errors.add(:sport, t("workouts.import.errors.missing_sport"))
      return render :edit, status: :unprocessable_content
    end

    sport = find_sport
    changed = []
    equipment_before = @workout.equipment_ids.sort
    if sport && sport.id != @workout.sport_id
      changed << "sport"
      begin
        Workouts::SportChange.new(workout: @workout, sport:).call!
      rescue Workouts::SportChange::MissingOriginalFile
        @workout.errors.add(:sport, t("workouts.update.sport_change.missing_original_file"))
        return render :edit, status: :unprocessable_content
      rescue Workouts::SportChange::ReanalysisFailed => error
        @workout.errors.add(:sport, t("workouts.update.sport_change.failed", message: error.message))
        return render :edit, status: :unprocessable_content
      end
    end

    if @workout.update(edit_params)
      # A member-typed title is theirs: the summary card never proposes another
      # one (docs/dev/AI.md §5).
      @workout.update_columns(title_source: "owner") if @workout.saved_change_to_title?
      changed.concat(Webhooks::Events.changed_fields(@workout.saved_changes, %w[title description notes commute]))
      Equipments::Totals.sync(@workout, workout_params[:equipment_ids])
      changed << "equipment_ids" if @workout.reload.equipment_ids.sort != equipment_before
      Webhooks::Events.workout_updated(@workout, changed)
      redirect_to workout_path(@workout), notice: t("workouts.update.success")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    Workouts::WorkoutDeletion.new(user: current_user, workout: @workout).call!
    redirect_to workouts_path, notice: t("workouts.destroy.success")
  end

  def publish
    publication = Workouts::Publisher.new(
      user: current_user, workout: @workout, profile: selected_profile, delay: publish_delay, **photo_choice
    ).call!
    redirect_to workout_path(@workout), notice: publication_notice(publication)
  rescue Workouts::Publisher::PublicationError => error
    redirect_to workout_path(@workout), alert: error.message
  end

  # Withdraws the publication the row names, or every active one from the
  # card header (docs/dev/PUBLISHING.md).
  def destroy_publication
    publication = (named_publication(@workout.active_publications) if params[:publication_id].present?)
    Workouts::PublicationDeletion.new(user: current_user, workout: @workout, publication:).call!
    redirect_to workout_path(@workout), notice: t("workouts.publication.destroy.success")
  end

  # Replaces the active publication the row names; without an active
  # publication to replace, publishes.
  def republish
    profile = selected_profile
    replaced = named_publication(@workout.active_publications) if params[:publication_id].present?
    publication = if replaced || @workout.active_publications.any?
      Workouts::PublicationReplacement.new(
        user: current_user, workout: @workout, profile:, delay: publish_delay, publication: replaced, **photo_choice
      ).call!.new_publication
    else
      Workouts::Publisher.new(user: current_user, workout: @workout, profile:, delay: publish_delay, **photo_choice).call!
    end
    redirect_to workout_path(@workout), notice: publication_notice(publication, republish: true)
  rescue Workouts::Publisher::PublicationError => error
    redirect_to workout_path(@workout), alert: error.message
  end

  # Leaves the safety delay early. The publication was never visible, so this
  # is the owner's deliberate second action, not a publish button.
  def activate_publication
    publication = scheduled_publication_param

    Workouts::ScheduledPublicationActivation.new(publication:, force: true, notify: false).call!
    redirect_to workout_path(@workout),
                notice: t("workouts.publication.activate.success", audience: t("publishing_profiles.audiences.#{publication.reload.audience}"))
  end

  # Moves the planned moment within the preset range; the frozen snapshot is
  # untouched.
  def reschedule_publication
    result = Workouts::ScheduledPublicationReschedule.new(
      user: current_user, workout: @workout, delay: publish_delay, publication: scheduled_publication_param
    ).call!
    redirect_to workout_path(@workout),
                notice: t("workouts.publication.reschedule.success", time: view_context.l(result.scheduled_for, format: :long))
  rescue Workouts::Publisher::PublicationError => error
    redirect_to workout_path(@workout), alert: error.message
  end

  # Nothing was shared yet, so cancellation is terminal and local: no Delete
  # activity, no remote trace.
  def destroy_scheduled_publication
    Workouts::ScheduledPublicationCancellation.new(user: current_user, publication: scheduled_publication_param).call!
    redirect_to workout_path(@workout), notice: t("workouts.publication.schedule_cancelled")
  end

  # The owner declines an automatic publication still waiting for the
  # enrichments (docs/dev/AUTO-PUBLISHING.md): it is settled as skipped and
  # nothing is published. A publication it already made is withdrawn like any
  # other.
  def destroy_auto_publication
    rows = @workout.auto_publications.waiting
    rows = rows.where(audience: params[:audience]) if params[:audience].present?
    rows.each do |row|
      row.with_lock { row.settle!("skipped", reason: "cancelled_by_owner") if row.waiting? }
    end
    redirect_to workout_path(@workout, anchor: "section-sharing"), notice: t("auto_publications.cancel.success")
  end

  # Owner-scoped, read-only candidate preview. Renders the exact projection
  # publishing would store, without persisting anything. Turbo Frame requests
  # get the viewer-shaped preview card; the JSON contract remains available for
  # the projection proofs.
  def publication_preview
    profile = selected_profile
    result = Workouts::PublicationPreview.new(user: current_user, workout: @workout, profile:).call

    response.headers["Cache-Control"] = "private, no-store"
    # A candidate with failing included media still renders its details (200)
    # with ready:false so a client can disable Publish and explain what is not
    # ready. Only route/privacy failures without a candidate are 422. JSON
    # only: the workout page lists what a profile shares instead of projecting
    # it (DESIGN.md §19.1).
    if result.candidate
      respond_to do |format|
        format.json { render json: preview_payload(result) }
      end
    else
      respond_to do |format|
        format.json do
          render json: {
            ready: false,
            blocking_error: result.blocking_error,
            warnings: [],
            preview_text: nil
          }, status: :unprocessable_content
        end
      end
    end
  end

  def delivery_refresh
    publication = named_or_sole_publication(@workout.active_publications)

    Workouts::DeliveryRefresh.new(publication:).call!
    redirect_to workout_path(@workout), notice: t("workouts.delivery.refresh_success")
  end

  private

  # The held `EffortRecord` is the authority for the gold place (it also feeds
  # the header badge and the publication markers), so a derived first place
  # without the stored record is not shown as one; second and third come from
  # the read-time ranking.
  def best_effort_places
    held = @effort_records_held.map(&:distance_key)
    places = BestEfforts::PersonalPlaces.new(user: current_user, best_efforts: @best_efforts).call
    @best_efforts.each_with_object({}) do |effort, result|
      place = held.include?(effort.distance_key) ? 1 : places[effort.id]
      result[effort.id] = place if place && (place > 1 || held.include?(effort.distance_key))
    end
  end

  # The profile the publish form opens on: the first publishable profile whose
  # audience no live publication holds yet (docs/dev/PUBLISHING.md), so the form
  # adds a publication beside the existing ones. Shared by the publication form
  # and its shared-field lists.
  def selected_publishing_profile
    @profiles.find { |profile| profile.publishable? && @workout.live_audiences.exclude?(profile.audience) }
  end

  # A publication of this workout named by its short id in `publication_id`,
  # among `scope`; anything else is a 404.
  def named_publication(scope) = scope.find_by_short_id!(params[:publication_id].to_s)

  # The publication a row action names among `scope`; the only one when the
  # request names none.
  def named_or_sole_publication(scope)
    return named_publication(scope) if params[:publication_id].present?

    publications = scope.to_a
    raise ActiveRecord::RecordNotFound unless publications.one?

    publications.first
  end

  def scheduled_publication_param = named_or_sole_publication(@workout.scheduled_publications)

  def preview_payload(result)
    candidate = result.candidate
    display = Workouts::PublicationView.new(preview_publication(candidate), principal: preview_principal)
    metrics = helpers.workout_metric_items(display).map do |item|
      { key: item.fetch(:key).to_s, label: item.fetch(:label), value: helpers.strip_tags(helpers.workout_metric_value(item)) }
    end
    track = display.track
    {
      ready: result.ready?,
      blocking_error: nil,
      warnings: result.warnings.map { |warning| t("workouts.publish.warnings.#{warning}") },
      preview_text: helpers.publication_preview_text(result.profile),
      title: display.title,
      description: display.description,
      sport: helpers.sport_display_name(display.sport),
      started_at: helpers.format_started_at(display.started_at),
      metrics:,
      route: {
        included: candidate.profile_snapshot.dig("settings", "route") == true,
        segments_count: candidate.route_metadata["segments_count"],
        visible_points_count: candidate.filtered_points_count,
        summary: helpers.workout_map_summary(display, segment_count: Array(track&.fetch("features", nil)).size),
        points: t("workouts.show.track_segments.points", count: candidate.filtered_points_count),
        geojson: track
      },
      gpx: candidate.media_readiness["gpx"].merge("label" => t("publishing_profiles.settings.gpx")),
      route_image: candidate.media_readiness["route_image"].merge("label" => t("publishing_profiles.settings.route_image")),
      route_excluded: t("workouts.publish.preview.route_excluded"),
      no_route: t("workouts.publish.preview.no_route"),
      media_not_ready: t("workouts.publish.preview.media_not_ready"),
      labels: {
        title: t("workouts.publish.preview.labels.title"),
        description: t("workouts.publish.preview.labels.description"),
        sport: t("workouts.publish.preview.labels.sport"),
        started: t("workouts.publish.preview.labels.started"),
        metrics: t("workouts.publish.preview.labels.metrics"),
        route: t("workouts.publish.preview.labels.route"),
        media: t("workouts.publish.preview.labels.media")
      }
    }
  end

  # In-memory publication mirroring exactly what publishing would store, so
  # the preview reuses the same view and formatting helpers as real pages.
  def preview_publication(candidate)
    WorkoutPublication.new(
      workout: @workout,
      publishing_profile: candidate_profile_for(candidate),
      profile_snapshot: candidate.profile_snapshot,
      privacy_zone_fingerprint: candidate.privacy_zone_fingerprint,
      route_metadata: candidate.route_metadata,
      representation: candidate.representation,
      filtered_points_count: candidate.filtered_points_count,
      has_route: candidate.has_route
    )
  end

  def candidate_profile_for(candidate)
    PublishingProfile.new(
      user: current_user,
      audience: candidate.profile_snapshot["audience"],
      settings: candidate.profile_snapshot["settings"]
    )
  end

  # A preview is owner-scoped, so the owner's browser principal is the viewer a
  # followers profile would serve; the fail-closed anonymous principal would
  # hide the very route the preview exists to show.
  def preview_principal
    Workouts::PublicationPrincipal.browser(current_user)
  end

  # A confirmed (or pending) participant reaches a source workout the
  # publication policy would hide from them (docs/dev/SHARED-ACTIVITIES.md): they read
  # the credited metrics-only presentation while it is unpublished, and the
  # standard publication presentation once it is published. Everyone else
  # follows the publication policy and gets a 404.
  def set_workout_for_show
    @workout = Workout.find_by_short_id!(params[:id])
    @participant_participation = participant_participation unless @workout.user == current_user
    return if @workout.user == current_user || @workout.viewable_by?(current_user, level: :workout)
    raise ActiveRecord::RecordNotFound unless @participant_participation
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # An invitation admits its invitee at once: the owner chose to share. A
  # detection admits nobody until both accounts confirmed, since a suggestion
  # discloses a title and a date, never the counterpart's metrics
  # (docs/dev/SHARED-ACTIVITIES.md).
  def participant_participation
    actor = current_user&.actor
    return unless actor

    @workout.workout_participations.active.where(participant_actor: actor)
      .where("origin = 'invitation' OR (owner_confirmed_at IS NOT NULL AND participant_confirmed_at IS NOT NULL)")
      .first
  end

  # Every figure of a manual entry is editable (docs/dev/MANUAL-ENTRY.md).
  def update_manual
    @manual_form = ManualWorkoutForm.from_params(params.fetch(:manual_workout, {}).permit(*ManualWorkoutsController::PERMITTED),
                                                 user: current_user)
    attributes = @manual_form.to_attributes
    if attributes
      result = Workouts::ManualEntry.new(workout: @workout).call(attributes, equipment_ids: @manual_form.submitted_equipment_ids)
      return redirect_to workout_path(@workout), notice: t("workouts.update.success") if result.success?

      @manual_form.adopt_errors(result.workout)
    end
    render :edit, status: :unprocessable_content
  end

  def refuse_credit_row
    raise ActiveRecord::RecordNotFound if @workout.credit?
  end

  def set_owned_workout
    @workout = current_user.workouts.find_by_short_id!(params[:id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def find_sport
    sport_id = workout_params[:sport_id]
    return nil if sport_id.blank?

    Sport.find_by(id: sport_id)
  end

  def invalid_sport_selection?
    workout_params[:sport_id].present? && find_sport.nil?
  end

  def workout_params
    params.fetch(:workout, {}).permit(:title, :description, :notes, :sport_id,
                                      :commute, equipment_ids: [])
  end

  def set_equipments
    @equipments = current_user.equipments.includes(:equipment_type).order(is_active: :desc, label: :asc, id: :asc)
  end

  def edit_params
    params.require(:workout).permit(:title, :description, :notes, :commute)
  end

  def ensure_publishing_profiles
    return unless @workout.user == current_user

    PublishingProfile.ensure_built_ins_for!(current_user)
  end

  # The publish form's photo list (docs/dev/PHOTOS.md): `photo_selection`
  # marks that a list was shown, so an empty choice shares no photo; without
  # it the default selection applies.
  def photo_choice
    return {} unless params[:photo_selection].present?

    {
      photo_ids: Array(params[:photo_ids]).map(&:to_s).compact_blank,
      photos_acknowledged: ActiveModel::Type::Boolean.new.cast(params[:photos_acknowledged]) == true
    }
  end

  def publication_readiness
    return {} unless @workout.user == current_user

    @profiles.each_with_object({}) do |profile, statuses|
      result = Workouts::PublicationReadiness.new(user: current_user, workout: @workout, profile:).call
      statuses[profile.id.to_s] = {
        "ready" => result.ready?,
        "warnings" => result.warnings.map { |warning| t("workouts.publish.warnings.#{warning}") },
        "preview" => helpers.publication_preview_text(profile),
        "shared" => helpers.publication_preview_fields(profile),
        "withheld" => helpers.publication_withheld_fields(profile),
        # The publish form shows its photo choice only for a profile that
        # shares photos (docs/dev/PHOTOS.md, DESIGN.md §19.35).
        "photos" => profile.settings["photos"] == true,
        "delay" => profile.publish_delay_seconds
      }
    end
  end

  # Text equivalent for the workout profile (DESIGN.md §18.7): the same
  # source the chart endpoint serves, sampled to a readable row count.
  CHART_TABLE_POINTS = 30

  def chart_table_points
    if @workout.user == current_user && !@reader_preview
      sample_chart_rows(Allure::Gpx::ChartSeries.new(
        workout_started_at: @workout.started_at,
        segments: @workout.track_segments,
        max_points: CHART_TABLE_POINTS,
        series: Allure::Gpx::ChartSeries::SERIES_KEYS.keys,
        extra_values: Workouts::WeatherChartValues.call(@workout)
      ).call)
    else
      publication_chart_points(@publication)
    end
  end

  def publication_chart_points(publication)
    policy = Workouts::PublicationPolicy.new(
      publication:,
      principal: Workouts::PublicationPrincipal.browser(current_user)
    )
    return [] unless policy.allowed?(resource: :chart)

    sample_chart_rows(Array(publication&.representation&.dig("chart")))
  end

  # The participant's credit row (docs/dev/SHARED-ACTIVITIES.md): its own analysis
  # rows, the convert action while attached, and the source's map and profile
  # only through the publication the participant may read, never the source's
  # raw track.
  def show_credit
    source = @workout.credited_from
    @credit_publication = Workouts::PublicationResolver.new(workout: source, user: current_user).call if source
    @credit_remote_view = credit_remote_view
    @credit_display = if @credit_publication
      Workouts::PublicationView.new(@credit_publication, principal: Workouts::PublicationPrincipal.browser(current_user))
    end
    @chart_table = @credit_publication ? publication_chart_points(@credit_publication) : []
    @chart_available_series = Allure::Gpx::ChartSeries::SERIES_KEYS.keys.select do |key|
      @chart_table.any? { |point| !point[key].nil? }
    end

    @segment_efforts = @workout.segment_efforts.includes(:segment).order(:started_at, :segment_id, :occurrence_index)
    @segment_effort_places = Segments::PersonalPlaces.new(user: current_user, efforts: @segment_efforts).call
    @segment_effort_gaps = Segments::PersonalBestGaps.new(user: current_user, efforts: @segment_efforts).call
    @best_efforts = @workout.best_efforts.order(:duration_seconds).to_a
    @effort_records_held = @workout.effort_records.to_a
    @best_effort_places = best_effort_places

    actor = current_user.actor
    @credit_participation = if source && actor
      WorkoutParticipation.live.credits.find_by(workout_id: source.id, participant_actor: actor)
    end
    render :credit
  end

  # A remote credit's map is its received note's, while the note is active
  # and the account may still read it (docs/dev/SHARED-ACTIVITIES.md).
  def credit_remote_view
    note = @workout.remote_participation&.remote_note
    return unless note&.active?

    policy = Federation::RemoteNotePolicy.new(note:, principal: Workouts::PublicationPrincipal.browser(current_user))
    Federation::RemoteNoteView.new(note) if policy.allowed?(resource: :note)
  end

  def sample_chart_rows(raw)
    rows = raw.filter_map do |point|
      normalized = point.to_h.symbolize_keys
      next if normalized[:distance].nil? || normalized[:elapsed_time].nil?

      normalized.slice(:distance, :elapsed_time, *Allure::Gpx::ChartSeries::SERIES_KEYS.keys,
                       *Workouts::WeatherChartValues::KEYS)
    end
    step = (rows.length / CHART_TABLE_POINTS.to_f).ceil
    return [] if step.zero?

    rows.each_slice(step).map(&:first)
  end

  def selected_profile
    profile = if params[:publishing_profile_id].present?
      current_user.publishing_profiles.find(params[:publishing_profile_id])
    else
      current_user.publishing_profiles.find_by!(built_in_key: "public")
    end
    raise ActiveRecord::RecordNotFound unless profile.publishable?

    profile
  end

  # The publish-time override, as seconds. An absent value falls back to the
  # profile policy inside the service; any value outside the presets makes the
  # service fail closed.
  def publish_delay
    value = params[:publish_delay].presence
    return nil unless value

    Integer(value, exception: false)
  end

  # The immediate path is the default; a hold reports its planned moment and
  # makes clear that nothing was shared yet.
  def publication_notice(publication, republish: false)
    audience = t("publishing_profiles.audiences.#{publication.audience}")
    if publication.scheduled?
      t("workouts.publish.scheduled",
        audience:,
        time: view_context.l(publication.scheduled_for, format: :long))
    elsif republish
      t("workouts.publish.republish.success")
    else
      t("workouts.publish.success", audience:)
    end
  end

  # Workout list filters (§13), delegated to the shared query object so the
  # bulk selection replays exactly this list (docs/dev/BULK-ACTIONS.md). Every
  # filter is a URL parameter: back/forward work and a filtered view is
  # shareable. Filtering never resets the sort; pagination preserves the params.
  def list_query = @list_query ||= Workouts::ListQuery.new(user: current_user, params: params)

  def filter_sport_ids = list_query.sport_ids
  def filter_period = list_query.period

  def filter_publication = list_query.publication
  def filter_commute = list_query.commute
  def filter_query = list_query.query
  def filter_place = list_query.place

  def filter_sort_key = list_query.sort_key
  def filter_sort = list_query.sort
  def filter_direction = list_query.direction

  # The equipment the bulk bar can attach or detach. Loaded only for the table
  # view, where the bulk selection lives (docs/dev/BULK-ACTIONS.md).
  def bulk_equipments
    return [] unless @view == "table"

    current_user.equipments.includes(:equipment_type).order(is_active: :desc, label: :asc, id: :asc)
  end

  # The sport pills (§13.2): the account's own sports, most used first, with
  # their counts. The ranking reads every workout, so an active filter never
  # hides the pill that would undo it; ties read alphabetically like the
  # catalog.
  def practiced_sports
    counts = current_user.workouts.group(:sport_id).count
    sports = Sport.alphabetical(Sport.where(id: counts.keys))
    positions = sports.each_with_index.to_h { |sport, index| [ sport.id, index ] }

    sports
      .map { |sport| { sport:, count: counts.fetch(sport.id) } }
      .sort_by { |entry| [ -entry[:count], positions.fetch(entry[:sport].id) ] }
  end
end
