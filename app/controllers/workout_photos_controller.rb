# frozen_string_literal: true

class WorkoutPhotosController < ApplicationController
  before_action :set_workout
  before_action :set_photo, only: %i[show update destroy retry placement]
  before_action :set_photo_page, only: %i[index update destroy retry placement time_offset sort]

  # The owner's photo page (DESIGN.md §20.24): the route on the left, the
  # manager on the right. A frame request from the manager's own list renders
  # that list alone.
  def index
    return unless request.headers["Turbo-Frame"] == helpers.photo_manager_frame_id(@workout)

    render partial: "workout_photos/manager", locals: manager_locals
  end

  # The card's gallery on the workout page (DESIGN.md §10.22), still a frame.
  def gallery
    render partial: "workout_photos/gallery", locals: { workout: @workout }
  end

  def create
    photo = Workouts::PhotoUpload.new(user: current_user, workout: @workout).call(params[:file])
    render json: { id: photo.to_param }, status: :created
  rescue Workouts::PhotoUpload::Invalid => error
    render json: { error: error.message }, status: :unprocessable_content
  end

  def show
    variant = %w[original display thumbnail].include?(params[:variant]) ? params[:variant] : "display"
    attachment = @photo.public_send(variant)
    raise ActiveRecord::RecordNotFound unless attachment.attached? && (variant == "original" || @photo.ready?)

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_data attachment.download, filename: attachment.filename.to_s, type: attachment.content_type,
      disposition: variant == "original" ? "attachment" : "inline"
  rescue ActiveStorage::FileNotFoundError
    raise ActiveRecord::RecordNotFound
  end

  def update
    if @photo.update(caption: params.require(:photo).permit(:caption)[:caption])
      respond_to do |format|
        format.json { render json: { caption: @photo.caption, label: helpers.workout_photo_label(@photo, @photo.position) } }
        format.html { render_photos }
      end
    else
      respond_to do |format|
        format.json { render json: { error: t("photos.errors.caption") }, status: :unprocessable_content }
        format.html { render_photos(status: :unprocessable_content, error: t("photos.errors.caption")) }
      end
    end
  end

  # The whole order in one request (docs/dev/PHOTOS.md); the owner's order
  # stops the automatic capture-time pass until « Trier ».
  def order
    current_user.with_lock do
      @workout.with_lock do
        photos = @workout.photos.to_a
        ids = Array(params[:ids]).map(&:to_s)
        raise ActiveRecord::RecordNotFound unless ids.sort == photos.map(&:to_param).sort

        @workout.update!(photos_ordered_by_owner: true)
        photos.each { |photo| photo.update!(position: ids.index(photo.to_param)) }
      end
    end
    head :no_content
  end

  # « Trier par heure de prise de vue » resumes the automatic order.
  def sort
    Workouts::PhotoOrder.new(workout: @workout).resume_automatic!
    render_photos
  end

  # The owner's placement (docs/dev/PHOTOS.md): drop the photo on the track
  # from the map, take its position away, or hand it back to the automatic
  # placement. Only a ready photo of a recording with a track is placed.
  def placement
    raise ActiveRecord::RecordNotFound unless @photo.ready? && @workout.positioned?

    placement = Workouts::PhotoPlacement.new(workout: @workout)
    case params[:mode]
    when "manual"
      longitude = Float(params[:longitude], exception: false)
      latitude = Float(params[:latitude], exception: false)
      valid = longitude&.between?(-180, 180) && latitude&.between?(-90, 90)
      unless valid && placement.place(@photo, longitude:, latitude:)
        return render json: { error: t("photos.placement.too_far") }, status: :unprocessable_content
      end

      Workouts::PhotoOrder.new(workout: @workout).apply
      render json: { id: @photo.to_param }
    when "clear"
      placement.clear(@photo)
      Workouts::PhotoOrder.new(workout: @workout).apply
      render_photos
    when "auto"
      placement.automatic(@photo)
      Workouts::PhotoOrder.new(workout: @workout).apply
      render_photos
    else
      head :unprocessable_content
    end
  end

  # The camera-clock correction, in minutes, applied to every photo placed
  # from its capture time.
  def time_offset
    raise ActiveRecord::RecordNotFound unless @workout.positioned?

    minutes = Integer(params[:offset_minutes].to_s.strip, exception: false)
    unless minutes&.between?(-840, 840)
      return render_photos(status: :unprocessable_content, error: t("photos.placement.offset_invalid"))
    end

    @workout.update!(photo_time_offset_seconds: minutes * 60)
    Workouts::PhotoPlacement.new(workout: @workout).refresh_all
    Workouts::PhotoOrder.new(workout: @workout).apply
    render_photos
  end

  def retry
    @photo.with_lock { @photo.update!(status: "processing", failure_reason: nil) if @photo.failed? }
    Workouts::PhotoProcessJob.perform_later(@photo) if @photo.processing?
    render_photos
  end

  def destroy
    current_user.with_lock { @photo.destroy! }
    render_photos
  end

  private

  def set_workout
    raise ActiveRecord::RecordNotFound unless Allure::Photos::Config.enabled?

    @workout = current_user.workouts.authored.find_by_short_id!(params[:workout_id])
  end

  def set_photo
    @photo = @workout.photos.find_by_short_id!(params[:id])
  end

  def set_photo_page
    # A mutation re-reads the rows: the association may already hold the
    # instances the before_action loaded.
    @photos = @workout.photos.reload.includes(:display_attachment, :thumbnail_attachment).to_a
    @quota = Workouts::PhotoQuota.new(user: @workout.user)
    @placeable = @workout.positioned?
    @offset_minutes = @workout.photo_time_offset_seconds / 60
    @diagnoses = photo_diagnoses
  end

  # One track read for every unplaced photo on the page (docs/dev/PHOTOS.md).
  def photo_diagnoses
    return {} unless @placeable

    placement = Workouts::PhotoPlacement.new(workout: @workout)
    @photos.each_with_object({}) do |photo, diagnoses|
      diagnosis = placement.diagnose(photo)
      diagnoses[photo.id] = diagnosis if diagnosis
    end
  end

  def manager_locals(error: nil)
    { workout: @workout, photos: @photos, quota: @quota, placeable: @placeable,
      diagnoses: @diagnoses, offset_minutes: @offset_minutes, error: }
  end

  # A mutation answers the frame it came from (DESIGN.md §20.24), like the
  # comment card: the manager's list, the card's gallery, or — without
  # JavaScript — the page itself.
  def render_photos(status: :ok, error: nil)
    case request.headers["Turbo-Frame"]
    when helpers.photo_manager_frame_id(@workout)
      # The mutation changed rows the before_action had already loaded.
      set_photo_page
      render partial: "workout_photos/manager", locals: manager_locals(error:), status:
    when helpers.photo_gallery_frame_id(@workout)
      render partial: "workout_photos/gallery", locals: { workout: @workout, error: }, status:
    else
      # Without JavaScript a refusal keeps its status and its page; a success
      # returns to the page through the redirect.
      if status != :ok
        flash.now[:alert] = error if error
        return render :index, status:
      end

      redirect_to workout_photos_path(@workout), status: :see_other, alert: error
    end
  end
end
