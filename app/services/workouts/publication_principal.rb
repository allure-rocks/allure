# frozen_string_literal: true

module Workouts
  # Who is asking for a publication resource. The three origins are kept
  # distinct on purpose: a browser visitor with no session (`:anonymous`), a
  # signed-in browser account, and a protocol request that is either unsigned
  # (`:protocol_anonymous`) or carries the verified signer (`:remote_actor` /
  # `:local_actor`). "Public means registered" denies `:anonymous` on public
  # publications while the wire contract keeps serving `:protocol_anonymous`
  # to remote peers, which have no Allure account.
  PublicationPrincipal = Data.define(:kind, :user, :actor) do
    def self.anonymous
      new(kind: :anonymous, user: nil, actor: nil)
    end

    def self.browser(user)
      return anonymous unless user

      new(kind: :browser_user, user:, actor: nil)
    end

    # A protocol request. A nil actor is an unsigned fetch, not a browser
    # visitor: it stays eligible for public publications and media.
    def self.protocol(actor)
      return new(kind: :protocol_anonymous, user: nil, actor: nil) unless actor

      new(kind: actor.remote? ? :remote_actor : :local_actor, user: actor.user, actor:)
    end
  end
end
