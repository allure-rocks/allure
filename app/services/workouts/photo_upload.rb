# frozen_string_literal: true

module Workouts
  class PhotoUpload
    class Invalid < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(I18n.t("photos.errors.#{code}"))
      end
    end

    def initialize(user:, workout:)
      @user = user
      @workout = workout
    end

    def call(file)
      raise ActiveRecord::RecordNotFound unless Allure::Photos::Config.enabled? && @workout.user_id == @user.id && !@workout.credit?
      raise Invalid, :unavailable if @user.deactivated?

      io = file.respond_to?(:tempfile) ? file.tempfile : file
      io&.rewind
      body = io&.read(Allure::Photos::Config::MAX_BYTES + 1).to_s.b
      raise Invalid, :missing if body.empty?
      raise Invalid, :too_large if body.bytesize > Allure::Photos::Config::MAX_BYTES

      type = Allure::Photos::Signature.detect(body)
      raise Invalid, :unsupported_type unless type
      raise Invalid, :heic_unavailable if type == "image/heic" && !Allure::Photos::Config.heic_supported?

      blob = nil
      photo = nil
      @user.with_lock do
        @workout.with_lock do
          raise Invalid, :too_many if @workout.photos.count >= Allure::Photos::Config::MAX_PER_WORKOUT
          raise Invalid, :quota_exceeded unless PhotoQuota.new(user: @user).fits?(body.bytesize)

          blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(body), filename: "photo#{Allure::Photos::Signature.extension(type)}",
                                                       content_type: type, identify: false)
          photo = @workout.photos.build(user: @user, original_content_type: type, bytes_total: body.bytesize,
                                        position: (@workout.photos.maximum(:position) || -1) + 1)
          photo.original.attach(blob)
          photo.save!
        end
      end
      PhotoProcessJob.perform_later(photo)
      photo
    rescue StandardError
      # A rollback can leave uploaded bytes without a row. Never purge a blob
      # whose attachment committed (including when enqueueing itself failed).
      blob&.purge if blob&.persisted? && !blob.attachments.exists?
      raise
    end
  end
end
