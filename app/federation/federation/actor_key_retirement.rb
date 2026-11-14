# frozen_string_literal: true

module Federation
  # Destroys the private key of a tombstoned local actor only after every
  # event and delivery it signed has reached a terminal state. Until then the
  # key must survive so a queued withdrawal can still be signed.
  class ActorKeyRetirement
    Result = Data.define(:retired, :waiting)

    def initialize(now: Time.current, limit: 100)
      @now = now
      @limit = limit
    end

    def call
      retired = 0
      waiting = 0
      candidates.limit(@limit).find_each do |actor|
        if retireable?(actor)
          actor.update!(private_key_ciphertext: nil, private_key_retired_at: @now)
          retired += 1
        else
          waiting += 1
        end
      end
      Result.new(retired:, waiting:)
    end

    private

    def candidates
      Actor.local
        .where.not(tombstoned_at: nil)
        .where(private_key_retired_at: nil)
        .where.not(private_key_ciphertext: nil)
    end

    def retireable?(actor)
      events = FederationOutboxEvent.where(actor_id: actor.id)
      return false if events.where.not(status: FederationOutboxEvent::TERMINAL_STATUSES).exists?
      return false if FederationDelivery
        .where(outbox_event_id: events.select(:id))
        .where.not(status: FederationDelivery::TERMINAL_STATUSES).exists?

      true
    end
  end
end
