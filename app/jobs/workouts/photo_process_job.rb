# frozen_string_literal: true

module Workouts
  class PhotoProcessJob < ApplicationJob
    self.enqueue_after_transaction_commit = true
    queue_as :photos
    limits_concurrency to: 2, key: ->(*) { "photos" }, duration: 10.minutes
    discard_on ActiveJob::DeserializationError

    def perform(photo)
      return unless Allure::Photos::Config.enabled? && photo.processing? && !photo.user.deactivated?

      blobs = []
      ready = false
      photo.original.blob.open do |original|
        Allure::Photos::Processor.call(original.path) do |display, thumbnail, width, height, exif|
          photo.user.with_lock do
            photo.with_lock do
              next unless photo.processing?

              extra = display.size + thumbnail.size
              raise Allure::Photos::Processor::Invalid, "quota_exceeded" unless PhotoQuota.new(user: photo.user).fits?(extra)

              [ [ :display, display ], [ :thumbnail, thumbnail ] ].each do |name, file|
                blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: "#{name}.webp", content_type: "image/webp", identify: false)
                blobs << blob
                photo.public_send(name).attach(blob)
              end
              photo.update!(width:, height:, bytes_total: photo.original.byte_size + extra, status: "ready", failure_reason: nil,
                            taken_at_local: exif.taken_at_local, taken_at_utc_offset: exif.utc_offset,
                            exif_location: exif.position? ? PhotoPlacement::FACTORY.point(exif.longitude, exif.latitude) : nil)
              ready = true
            end
          end
        end
      end
      if ready
        place(photo)
        reorder(photo)
      end
    rescue Allure::Photos::Processor::Invalid => error
      mark_failed(photo, error.code)
    rescue ActiveRecord::RecordNotFound
      # The owner deleted the photo while it was being decoded.
      nil
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
      mark_failed(photo, "processing_error")
    ensure
      blobs&.each { |blob| blob.purge unless blob.attachments.exists? }
      # A waiting automatic publication waits for every photo (PLAN_PHOTOS.md §5.3).
      nudge(photo)
    end

    private

    # Placement is the owner's convenience: a failure leaves a ready, unplaced
    # photo rather than a failed one.
    def place(photo)
      PhotoPlacement.new(workout: photo.workout).refresh(photo.reload)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, photo_id: photo.id })
    end

    # The gallery follows the capture time (PLAN_PHOTOS.md §2.1); ordering is
    # never a reason to fail a processed photo.
    def reorder(photo)
      PhotoOrder.new(workout: photo.workout).apply
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, photo_id: photo.id })
    end

    # Not AutoPublishJob.nudge: a photo is not an analysis, so the
    # `workout.analyzed` webhook stays out of it.
    def nudge(photo)
      return unless photo && WorkoutAutoPublication.waiting.exists?(workout_id: photo.workout_id)

      AutoPublishJob.perform_later(photo.workout)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
    end

    def mark_failed(photo, reason)
      WorkoutPhoto.where(id: photo.id, status: "processing").update_all(status: "failed", failure_reason: reason, updated_at: Time.current)
    end
  end
end
