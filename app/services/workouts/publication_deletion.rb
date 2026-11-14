# frozen_string_literal: true

module Workouts
  # The owner's withdrawal from the workout page: one named active publication,
  # or every active one at once (PLAN_AUDIENCES.md §4). Each withdrawal keeps
  # its own Delete intent, addressed to the instances its Create reached.
  class PublicationDeletion
    def initialize(user:, workout:, publication: nil)
      @user = user
      @workout = workout
      @publication = publication
    end

    def call!
      return [ withdraw!(@publication) ] if @publication

      @workout.reset_publications
      active = @workout.active_publications.to_a
      return [ PublicationWithdrawal.new(user: @user, workout: @workout).call!.publication ] if active.empty?

      active.map { |publication| withdraw!(publication) }
    end

    private

    def withdraw!(publication)
      raise ActiveRecord::RecordNotFound unless publication.workout_id == @workout.id

      PublicationWithdrawal.new(user: @user, workout: @workout, publication:).call!.publication
    end
  end
end
