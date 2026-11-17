# frozen_string_literal: true

class SegmentsController < ApplicationController
  include Pagy::Method

  before_action :set_viewable_segment, only: :show
  before_action :set_owned_segment, only: %i[edit update destroy publish republish destroy_publication]
  before_action :set_source_workout, only: %i[new create]

  INDEX_KINDS = %w[segment route loop].freeze
  DISCOVER_TAB = "discover"

  helper_method :list_query

  def index
    requested = params[:kind].to_s
    @kind = (INDEX_KINDS + [ DISCOVER_TAB ]).include?(requested) ? requested : "segment"

    if @kind == DISCOVER_TAB
      load_discover
    else
      load_owned
    end

    # One batched read per page feeds every row's record and the viewer's
    # standing (docs/dev/SEGMENTS.md); a private course simply has no board.
    @podiums = Segments::Podiums.new(rows: @segments, viewer: current_user).call
  end

  def show
    @owner_view = @segment.user == current_user
    @publication = @segment.active_publication
    @publication_stale = @owner_view && @segment.publication_stale?
    if @owner_view && @segment.kind == "segment"
      @corridor_intersects = Segments::CorridorPreflight.intersects?(@segment)
    end
    # Every viewer only ever sees their own efforts here; the board is the
    # only cross-athlete surface (docs/dev/SEGMENTS.md).
    @efforts = if current_user
      @segment.segment_efforts
        .where(user: current_user)
        .includes(:workout, :sport)
        .order(:elapsed_time, :started_at, :id)
    else
      SegmentEffort.none
    end
    @effort_history = Allure::Segments::EffortHistory.new(@efforts.to_a)
    @opted_out = current_user && @segment.segment_opt_outs.exists?(user: current_user)
    # The board preview lives on the detail page (top 10 per sport); the full
    # board stays at /segments/:id/leaderboard. Only a shared course has one,
    # and each viewer reads their own (docs/dev/SEGMENTS.md).
    @board_scope = board_scope
    @board_sections = @segment.shareable? ? @segment.leaderboard_sections(viewer: current_user, scope: @board_scope) : []
    @standing = viewer_standing
    # A shared course counts the athletes this viewer sees ranked; a private
    # one is read by its owner alone (docs/dev/SEGMENTS.md).
    @participants_count = if @segment.shareable?
      Segments::Listing.participants_count(@segment, viewer: current_user)
    else
      @segment.participants_count
    end
    @reach = Segments::Reach.new(segment: @segment, user: current_user).call
    # The frozen course profile (docs/dev/SEGMENTS.md): a stored bounded
    # snapshot, never recomputed here. The chart endpoint serves the same
    # points; this is the text equivalent (DESIGN.md §15.1).
    @segment_chart_table = Allure::Segments::ElevationProfile.table(@segment)
  end

  def new
    @segment = current_user.segments.new(
      kind: "segment",
      visibility: "private",
      match_tolerance_meters: Segments::Creator::DEFAULT_MATCH_TOLERANCE_METERS,
      source_workout: @workout,
      sport: @workout.sport
    )
    @corridor_intersects = Segments::CorridorPreflight.intersects?(@segment)
  end

  def create
    @segment = Segments::Creator.new(
      user: current_user,
      workout: @workout,
      name: segment_params[:name],
      description: segment_params[:description],
      start_index: segment_params[:source_start_index],
      end_index: segment_params[:source_end_index],
      match_tolerance_meters: segment_params[:match_tolerance_meters],
      sport: selected_sport,
      visibility: segment_params[:visibility],
      zone_acknowledged: ActiveModel::Type::Boolean.new.cast(segment_params[:acknowledge_privacy_zones]) == true
    ).call

    if @segment.persisted?
      redirect_to segment_path(@segment), notice: t("segments.create.success")
    else
      # The failed draft carries the derived corridor, so the re-render can ask
      # for the privacy-zone acknowledgment the model refused.
      @corridor_intersects = Segments::CorridorPreflight.intersects?(@segment)
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @corridor_intersects = Segments::CorridorPreflight.intersects?(@segment)
  end

  def update
    attributes = update_params
    @segment = Segments::Updater.new(
      segment: @segment,
      attributes: attributes.except("acknowledge_privacy_zones"),
      zone_acknowledged: ActiveModel::Type::Boolean.new.cast(attributes[:acknowledge_privacy_zones]) == true
    ).call
    if @segment.errors.empty?
      redirect_to segment_path(@segment), notice: t("segments.update.success")
    else
      @corridor_intersects = Segments::CorridorPreflight.intersects?(@segment)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    Segments::SegmentDeletion.new(user: current_user, segment: @segment).call!
    redirect_to segments_path, notice: t("segments.destroy.success")
  end

  def publish
    Segments::Publisher.new(user: current_user, segment: @segment).call!
    redirect_to segment_path(@segment), notice: t("segments.publish.success")
  rescue Segments::Publisher::PublicationError => error
    redirect_to segment_path(@segment), alert: error.message
  end

  def republish
    if @segment.active_publication
      Segments::PublicationReplacement.new(user: current_user, segment: @segment).call!
    else
      Segments::Publisher.new(user: current_user, segment: @segment).call!
    end
    redirect_to segment_path(@segment), notice: t("segments.publish.republish.success")
  rescue Segments::Publisher::PublicationError => error
    redirect_to segment_path(@segment), alert: error.message
  end

  def destroy_publication
    Segments::PublicationWithdrawal.new(user: current_user, segment: @segment).call!
    redirect_to segment_path(@segment), notice: t("segments.publication.destroy.success")
  end

  private

  def list_query = @list_query ||= Segments::ListQuery.new(viewer: current_user, params:, kind: @kind)

  def board_scope = Segments::Listing::SCOPES.include?(params[:board]) ? params[:board] : "everyone"

  # The viewer's best rank across the board's sport sections, derived from the
  # board already loaded: no extra query, and a private course has none. An
  # unlisted effort is reported by the detail tiles through @efforts. A viewer
  # who declared a category also reads their place in it, once the category
  # is offered on that ranking (docs/dev/SEGMENTS.md).
  def viewer_standing
    return nil unless current_user && @segment.shareable?

    @board_sections.filter_map do |_sport, efforts|
      index = efforts.index { |effort| effort.user_id == current_user.id }
      index && { rank: index + 1, total: efforts.size, **category_standing(efforts) }
    end.min_by { |row| row[:rank] }
  end

  def category_standing(efforts)
    category = current_user.leaderboard_category
    ranking = Segments::Categories.filter?(category) && Segments::Categories.ranking(efforts, category)
    return {} unless ranking

    { category:, category_rank: ranking.index { |effort| effort.user_id == current_user.id } + 1, category_total: ranking.size }
  end

  # The discover page (docs/dev/SEGMENTS.md): the map alone, showing every
  # course the viewer may see — the readable shared ones and their own, private
  # ones included — with no filter. Nothing here renders cards.
  def load_discover
    @discover_available = Segment
      .visible_to(current_user)
      .where(kind: "segment", active: true)
      .exists?
    @discover_map_center = discover_map_center
    @segments = []
  end

  # The map opens on the viewer's own position when the browser grants it;
  # this is only the fallback underneath: the start point of the most recent
  # workout, so the first screen is usually already meaningful. Without any
  # activity the client keeps its default centre until the first payload fits.
  def discover_map_center
    start_point = current_user.workouts.positioned.order(started_at: :desc).limit(1).pick(:start_point)
    return nil if start_point.nil?

    [ start_point.x, start_point.y ]
  end

  # Every course the viewer may see, one kind at a time (docs/dev/SEGMENTS.md
  # §8.4): the readable shared ones and their own, private ones included.
  # Routes and loops are never shared, so those kinds only ever hold their
  # owner's courses. The viewer's own inactive courses stay listed so they
  # remain manageable; another owner's inactive course is not offered.
  def load_owned
    scope = Segment
      .visible_to(current_user)
      .where(kind: @kind)
      .where("segments.user_id = :viewer OR segments.active = true", viewer: current_user.id)
    @unfiltered_count = scope.count
    @practiced_sports = list_query.practiced_sports(scope)
    @pagy, @segments = pagy(list_query.resolve(scope.includes(:sport, :user)), limit: 20)
  end

  # The course itself is readable at its own `visibility` level; the board is
  # governed separately by `leaderboard_viewable_by?`. Denial is 404, never
  # 403 (docs/dev/SEGMENTS-FEDERATION.md).
  def set_viewable_segment
    @segment = Segment.find_by_short_id!(params[:id])
    raise ActiveRecord::RecordNotFound unless @segment.viewable_by?(current_user)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def set_owned_segment
    @segment = current_user.segments.find_by_short_id!(params[:id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def set_source_workout
    @workout = current_user.workouts.positioned.find_by_short_id!(params[:workout_id])
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def segment_params
    params.fetch(:segment, {}).permit(
      :name, :description, :source_start_index, :source_end_index, :match_tolerance_meters, :sport_id,
      :visibility, :acknowledge_privacy_zones
    )
  end

  def update_params
    params.require(:segment).permit(
      :name, :description, :match_tolerance_meters, :active, :visibility, :sport_id,
      :acknowledge_privacy_zones
    )
  end

  # A missing `sport_id` inherits the source workout's sport (older callers);
  # a blank one means every sport is eligible.
  def selected_sport
    return Segments::Creator::INHERIT_SPORT unless segment_params.key?(:sport_id)

    value = segment_params[:sport_id]
    return nil if value.blank?

    Sport.find(value)
  end
end
