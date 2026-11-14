# frozen_string_literal: true

module Api
  module Rest
    module V1
      # File imports through the API (PLAN_API.md §6.3, §8): the web's batch
      # upload with the `api` trigger, or with `source=strava_archive` one
      # Strava archive (PLAN_STRAVA_ARCHIVE.md §8). The response returns once
      # the batch and its files are stored, before any parsing; the ordinary
      # pipeline does the rest, deduplication and automatic publishing
      # included.
      class ImportsController < BaseController
        require_scope "import", "read", only: %i[index show]
        require_scope "import", only: %i[create destroy]
        rate_limit to: 20, within: 1.hour, by: -> { Current.api_token.id }, name: "api-imports", only: :create,
                   with: -> { render_rate_limited(1.hour) }
        idempotent only: :create

        def index
          scope = current_user.workout_import_batches.includes(:sport)
          render json: paginate(scope, column: :created_at, direction: :desc, context: "imports") { ImportSerializer.new(it).as_json }
        end

        def show
          batch = owned_batch
          render json: detail(batch)
        end

        SOURCES = [ "file", Allure::ImportSources::STRAVA_ARCHIVE.key ].freeze

        def create
          source = params[:source].presence || "file"
          unless source.is_a?(String) && SOURCES.include?(source)
            return render_validation([ { field: "source", code: "unknown_source",
                                         detail: "source is one of #{SOURCES.join(', ')}." } ])
          end
          return create_strava_archive if source == Allure::ImportSources::STRAVA_ARCHIVE.key

          files = Array(params[:files]).compact_blank
          sport = Sport.find_by(slug: params[:fallback_sport].to_s, active: true) if params[:fallback_sport].is_a?(String)
          errors = upload_errors(files) + sport_errors(sport)
          return render_validation(errors) if errors.any?

          batch = current_user.workout_import_batches.new(source: "file", trigger: "api", sport:,
                                                          notes: params[:notes].presence)
          return render_validation(field_errors(batch, rename: { sport: :fallback_sport })) unless batch.valid?

          batch.source_bytes = files.sum { it.size.to_i }
          return if refuse_admission(batch)

          WorkoutImportBatch.transaction do
            batch.save!
            batch.source_files.attach(files)
          end
          Workouts::ImportBatchJob.perform_later(batch)

          response.headers["Location"] = api_url("/api/rest/v1/imports/#{batch.to_param}")
          render json: detail(batch), status: :accepted
        end

        # Asks a running import to stop, as the web's cancel; entries already
        # imported stay.
        def destroy
          batch = owned_batch
          return render_problem(:conflict, "import_finished") if batch.terminal?

          batch.cancel!
          render json: detail(batch), status: :accepted
        end

        private

        # One archive, an optional fallback sport, no notes: each activity
        # brings its own texts.
        def create_strava_archive
          files = Array(params[:files]).compact_blank
          sport = Sport.find_by(slug: params[:fallback_sport].to_s, active: true) if params[:fallback_sport].is_a?(String)
          errors = archive_errors(files)
          errors += sport_errors(sport) if params[:fallback_sport].present?
          return render_validation(errors) if errors.any?

          batch = current_user.workout_import_batches.new(source: Allure::ImportSources::STRAVA_ARCHIVE.key,
                                                          trigger: "api", sport:,
                                                          source_bytes: files.first.size.to_i)
          return if refuse_admission(batch)

          WorkoutImportBatch.transaction do
            batch.save!
            batch.source_files.attach(files.first)
          end
          Workouts::StravaArchiveImportJob.perform_later(batch)

          response.headers["Location"] = api_url("/api/rest/v1/imports/#{batch.to_param}")
          render json: detail(batch), status: :accepted
        end

        # The web's admission (PLAN_IMPORT_SOURCES.md §3.2): too many imports
        # waiting, or the day's upload budget spent, answers 429 with a reason.
        def refuse_admission(batch)
          refusal = in_english do
            Workouts::ImportAdmission.new(user: current_user, source: batch.source, bytes: batch.source_bytes).refusal
          end
          return false unless refusal

          response.headers["Retry-After"] = refusal.retry_after.to_s
          render_problem(:too_many_requests, "import_limit", detail: refusal.message, reason: refusal.reason)
          true
        end

        def archive_errors(files)
          if files.length != 1 || !files.first.is_a?(ActionDispatch::Http::UploadedFile)
            [ { field: "files", code: "one_archive", detail: "Send exactly one Strava archive as files[]." } ]
          elsif File.extname(files.first.original_filename.to_s).downcase != ".zip"
            [ { field: "files", code: "not_zip", detail: "Send the .zip file Strava sends." } ]
          elsif files.first.size.to_i > Allure::StravaArchive::MAX_BYTES
            [ { field: "files", code: "too_large",
                detail: "Send at most #{Allure::StravaArchive::MAX_SIZE_LABEL} in one archive." } ]
          else
            []
          end
        end

        def owned_batch = current_user.workout_import_batches.includes(:sport).find_by_short_id!(params[:id])

        def detail(batch)
          ImportSerializer.new(batch, entries: batch.entries.includes(:workout).order(:position)).as_json
        end

        def upload_errors(files)
          reader = Workouts::ArchiveReader
          if files.empty?
            [ { field: "files", code: "required", detail: "Send at least one file as files[]." } ]
          elsif !files.all?(ActionDispatch::Http::UploadedFile)
            [ { field: "files", code: "invalid_type", detail: "files[] must be uploaded files." } ]
          elsif files.length > reader::MAX_SOURCE_FILES
            [ { field: "files", code: "too_many", detail: "Send at most #{reader::MAX_SOURCE_FILES} files." } ]
          elsif files.sum { it.size.to_i } > reader::MAX_SOURCE_BYTES
            [ { field: "files", code: "too_large", detail: "Send at most 500 MB in one import." } ]
          else
            []
          end
        end

        def sport_errors(sport)
          return [] if sport

          if params[:fallback_sport].blank?
            [ { field: "fallback_sport", code: "required",
                detail: "Name the sport to use for files that do not record one (a slug from GET /sports)." } ]
          else
            [ { field: "fallback_sport", code: "unknown_sport", detail: "Unknown sport: #{params[:fallback_sport].inspect}." } ]
          end
        end
      end
    end
  end
end
