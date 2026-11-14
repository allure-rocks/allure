# frozen_string_literal: true

module Federation
  class RecoveryJob < ApplicationJob
    queue_as :federation

    def perform
      Outbox::Recovery.new.call
      Inbox::Recovery.new.call
      Workouts::ScheduledPublicationActivation.sweep
      Workouts::PublicationCleanup.sweep
      Segments::PublicationCleanup.sweep
      ActorKeyRetirement.new.call
      RemoteMedia::Recovery.new.call
    end
  end
end
