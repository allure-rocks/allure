# frozen_string_literal: true

module Federation
  module Safety
    # Bounds how many request threads may fetch a signer's actor at once
    # (PLAN_M5 §12.2). An inbox POST or a signed GET whose cached key does not
    # verify fetches the claimed actor inside the request thread; without a
    # bound, a few requests naming slow actor URIs would hold every web thread
    # and take the whole instance down. A request that finds the gate taken is
    # asked to retry (503), which every ActivityPub sender does; a request
    # whose cached key verifies never reaches the gate. The gate is per
    # process, so a single Puma process always keeps its other threads.
    module ResolutionGate
      SLOTS = 1

      class Busy < ActorResolver::Unavailable; end

      SEMAPHORE = Concurrent::Semaphore.new(SLOTS)

      module_function

      def hold
        raise Busy, "signer resolution is busy" unless SEMAPHORE.try_acquire

        begin
          yield
        ensure
          SEMAPHORE.release
        end
      end
    end
  end
end
