# frozen_string_literal: true

module Admin
  # Publication oversight (docs/dev/ADMIN.md): browse workout and course
  # publications with their audience, state and delivery tallies, and withdraw
  # an active publication through the immutable lifecycle. Takedown is
  # moderation over user content, so it is confirmed and audited.
  class PublicationsController < BaseController
    include Pagy::Method

    STATUSES = %w[active scheduled deleted].freeze
    AUDIENCES = %w[all public followers].freeze

    def index
      @kind = params[:kind] == "courses" ? "courses" : "workouts"
      @status = STATUSES.include?(params[:status]) ? params[:status] : "active"
      @audience = AUDIENCES.include?(params[:audience]) ? params[:audience] : "all"
      @statuses = STATUSES
      @audiences = AUDIENCES

      scope = @kind == "courses" ? courses_scope : workouts_scope
      @pagy, @publications = pagy(scope, limit: 20)
      @delivery = Publications::DeliveryRollup.new(kind: @kind, publication_ids: @publications.map(&:id)).call
    end

    def withdraw_workout
      publication = WorkoutPublication.find_by_short_id!(params[:id])
      # A scheduled publication was never shared, so operator takedown is a
      # local cancellation with no Delete activity (docs/dev/DELAYED-PUBLISHING.md).
      if publication.scheduled?
        result = Workouts::ScheduledPublicationCancellation.new(user: current_user, publication:, operator: true).call!
        audit(result.publication, kind: "workout", action: :publication_schedule_cancelled)
        redirect_to admin_publications_path(kind: "workouts", status: "scheduled"),
                    notice: t("admin.publications.flash.schedule_cancelled")
      else
        result = Workouts::PublicationWithdrawal.new(user: current_user, publication:, operator: true).call!
        audit(result.publication, kind: "workout")
        redirect_to admin_publications_path(kind: "workouts", status: "active"),
                    notice: t("admin.publications.flash.withdrawn")
      end
    end

    def withdraw_course
      publication = SegmentPublication.find_by_short_id!(params[:id])
      result = Segments::PublicationWithdrawal.new(user: current_user, publication:, operator: true).call!
      audit(result.publication, kind: "course")
      redirect_to admin_publications_path(kind: "courses", status: "active"),
                  notice: t("admin.publications.flash.withdrawn")
    end

    private

    def workouts_scope
      scope = @status == "deleted" ? WorkoutPublication.deleted : WorkoutPublication.where(status: @status)
      scope = scope.where(audience: @audience) if @audience != "all"
      scope.includes(:actor, workout: :user).order(published_at: :desc, id: :desc)
    end

    def courses_scope
      scope = @status == "deleted" ? SegmentPublication.deleted : SegmentPublication.where(status: @status)
      scope = scope.where(audience: @audience) if @audience != "all"
      scope.includes(:actor, segment: :user).order(published_at: :desc, id: :desc)
    end

    def audit(publication, kind:, action: :publication_withdrawn)
      owner = publication.respond_to?(:workout) ? publication.workout&.user : publication.segment&.user
      Audit.record(
        actor: current_user,
        action:,
        subject: publication,
        metadata: {
          "kind" => kind,
          "owner" => owner&.username || publication.actor&.handle,
          "audience" => publication.try(:audience)
        }.compact
      )
    end
  end
end
