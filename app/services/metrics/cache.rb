# frozen_string_literal: true

module Metrics
  # Process-local memoization for the database-derived snapshot. Every scrape
  # inside the TTL is nearly free; the first scrape after it pays for the
  # grouped counts once. There is no shared cache store (Solid Cache is
  # explicitly inactive in this repository), and a per-process value is
  # correct here: the gauges are identical in every process.
  module Cache
    TTL = 15.seconds

    MUTEX = Mutex.new

    module_function

    def fetch
      MUTEX.synchronize do
        current = Time.current
        refresh!(current) if @value.nil? || @expires_at.nil? || current >= @expires_at
        @value
      end
    end

    def reset!
      MUTEX.synchronize do
        @value = nil
        @expires_at = nil
      end
    end

    def refresh!(current)
      @value = Snapshot.new.call
      @expires_at = current + TTL
    end
  end
end
