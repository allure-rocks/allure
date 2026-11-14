# frozen_string_literal: true

module Federation
  # Resolves a user-supplied follow target to a local or remote actor. A bare
  # username or an @handle on this instance resolves locally; handles
  # (@name@domain, name@domain and acct:name@domain) go through WebFinger;
  # anything else is treated as an actor URI.
  class TargetResolver
    class InvalidTarget < StandardError; end

    def initialize(actor_resolver: nil, webfinger_resolver: nil, config: Allure::Federation.config)
      @config = config
      @actor_resolver = actor_resolver || ActorResolver.new(config:)
      @webfinger_resolver = webfinger_resolver || WebFingerResolver.new(config:)
    end

    def call!(target)
      value = target.to_s.strip
      raise InvalidTarget, "target is required" if value.blank?

      local_username?(value) ? resolve_local(value) : resolve_remote(value)
    end

    # Whether a value resolves on this instance without an outbound request.
    # Callers that only accept local targets (participation invitations before
    # the remote contract ships) refuse a remote handle before it is fetched.
    def local_target?(target)
      value = target.to_s.strip
      value.present? && local_username?(value)
    end

    private

    def local_username?(value)
      username, domain = split_handle(value)
      return false unless User::USERNAME_FORMAT.match?(username)
      return true if domain.blank?

      domain.casecmp?(@config.domain)
    end

    def resolve_local(value)
      username, = split_handle(value)
      user = User.find_by(username:)
      raise InvalidTarget, "unknown account" unless user

      Federation::ActorProvisioner.new(user:, config: @config).call!
    rescue Federation::ActorProvisioner::IdentityConflict => error
      raise InvalidTarget, error.message
    end

    def resolve_remote(value)
      actor = if handle_target?(value)
        @webfinger_resolver.resolve(value)
      else
        @actor_resolver.resolve(value)
      end
      raise InvalidTarget, "target must be a remote actor" if actor.local? || @config.local_uri?(actor.uri)
      raise InvalidTarget, "target is unavailable" if actor.tombstoned?
      raise InvalidTarget, "target is blocked" if Safety::Blocks.blocked?(actor.uri)

      actor
    rescue ActorResolver::InvalidActor, ActorResolver::FetchError,
           WebFingerResolver::InvalidHandle, WebFingerResolver::FetchError => error
      raise InvalidTarget, error.message
    end

    # A bare `name@domain` is the stored `Actor#acct`/`#handle` form, which
    # callers pass back verbatim as a follow or unfollow target. Only a value
    # with no scheme and no path can be a handle; every other value stays an
    # actor URI.
    def handle_target?(value)
      return true if value.start_with?("@", "acct:")
      return false if value.match?(/\A[a-z][a-z0-9+.\-]*:/i) || value.include?("/")

      value.count("@") == 1
    end

    def split_handle(value)
      handle = value.sub(/\A@/, "").sub(/\Aacct:/i, "")
      handle.split("@", 2)
    end
  end
end
