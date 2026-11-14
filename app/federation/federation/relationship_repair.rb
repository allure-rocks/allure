# frozen_string_literal: true

module Federation
  # Ends the live relationships a block or a remote account deletion left
  # behind before both ended them (`Following.end_with!`). Read-only unless
  # `apply: true`; a second run finds nothing.
  class RelationshipRepair
    Finding = Data.define(:following, :actor, :reason, :status)

    def initialize(now: Time.current)
      @now = now
    end

    def call(apply: false)
      findings.tap do |list|
        list.each { |finding| finding.following.undo!(at: @now) } if apply
      end
    end

    private

    def findings
      Following.active.includes(:follower_actor, :followed_actor).find_each.filter_map do |following|
        actor = [ following.follower_actor, following.followed_actor ].find(&:remote?)
        next unless actor

        reason = if actor.tombstoned? then "deleted"
        elsif Safety::Blocks.blocked?(actor.uri) then "blocked"
        end
        Finding.new(following, actor, reason, following.status) if reason
      end
    end
  end
end
