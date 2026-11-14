# frozen_string_literal: true

module Federation
  # The single visibility boundary for received notes and their media,
  # mirroring Workouts::PublicationPolicy. Anonymous visitors never see remote
  # copies; a followers note additionally requires an active entitlement
  # (PLAN_M5 §8.3, §14).
  class RemoteNotePolicy
    RESOURCES = %i[note track chart media react comment].freeze

    def initialize(note:, principal:)
      @note = note
      @principal = principal
    end

    def allowed?(resource: :note)
      resource = resource.to_sym
      return false unless RESOURCES.include?(resource)
      return false unless @note&.active?
      return false if @principal.kind == :anonymous

      return false unless @note.public? || entitled?

      resource_allowed?(resource)
    rescue ActiveRecord::RecordNotFound, KeyError, NoMethodError, TypeError
      false
    end

    private

    def resource_allowed?(resource)
      case resource
      when :note, :media, :react
        true
      when :comment
        # The origin's profile closed the thread on the wire; a thread closed
        # live is only learnt from its refusal (PLAN_COMMENTS.md §4.2).
        @note.representation["comments_closed"] != true
      when :track
        @note.representation["track"].is_a?(Hash) && Array(@note.representation.dig("track", "features")).any?
      when :chart
        @note.representation["chart"].is_a?(Array) && @note.representation["chart"].any?
      else
        false
      end
    end

    def entitled?
      actor = case @principal.kind
      when :browser_user then @principal.user&.actor
      when :local_actor then @principal.actor
      end
      return false unless actor

      @note.entitled_to?(actor)
    end
  end
end
