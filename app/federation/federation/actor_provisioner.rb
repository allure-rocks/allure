# frozen_string_literal: true

require "openssl"
require "uri"

module Federation
  class ActorProvisioner
    class IdentityConflict < StandardError; end

    RSA_BITS = 2048

    def initialize(user:, config: Allure::Federation.config, key_factory: nil)
      @user = user
      @config = config
      @key_factory = key_factory || -> { OpenSSL::PKey::RSA.generate(RSA_BITS) }
    end

    def call!
      raise IdentityConflict, "Actor provisioning requires a persisted user" unless @user.persisted?

      validate_username!
      actor_uri = @config.actor_uri(@user.username)
      validate_local_uri!(actor_uri)

      # Fast path, without a row lock: once provisioned, the actor never
      # changes identity, and every signed-in /feed and /people request lands
      # here. `with_lock` takes `FOR UPDATE` on the user row, which conflicts
      # with the `FOR KEY SHARE` every foreign-key check to `users` holds, so
      # the page would queue behind any import or rebuild transaction of the
      # account (best efforts, records, place names). Only first provisioning
      # needs the lock; the unique local-actor index covers the race.
      existing = Actor.find_by(user_id: @user.id, local: true)
      return validate_existing!(existing, actor_uri) if existing

      @user.with_lock do
        actor = @user.actor
        return validate_existing!(actor, actor_uri) if actor

        conflicting_actor = Actor.find_by(uri: actor_uri)
        raise IdentityConflict, "Actor URI is already assigned" if conflicting_actor

        key = @key_factory.call
        Actor.create!(
          user: @user,
          local: true,
          uri: actor_uri,
          handle: @config.handle(@user.username),
          display_name: @user.display_name,
          summary: @user.bio,
          public_key_id: @config.key_id(@user.username),
          public_key_pem: key.public_key.to_pem,
          private_key_ciphertext: key.to_pem,
          inbox_url: @config.inbox_uri(@user.username)
        )
      end
    rescue ActiveRecord::RecordNotUnique
      actor = @user.reload.actor
      return validate_existing!(actor, actor_uri) if actor

      raise IdentityConflict, "Actor identity could not be provisioned"
    end

    private

    def validate_username!
      return if @user.username == @user.username.to_s.downcase &&
        @user.username.match?(User::USERNAME_FORMAT)

      raise IdentityConflict, "Actor provisioning requires a canonical username"
    end

    def validate_local_uri!(actor_uri)
      return if @config.local_uri?(actor_uri)

      raise IdentityConflict, "Actor URI does not belong to the configured instance"
    rescue URI::InvalidURIError, Allure::Federation::Config::InvalidBaseUrl
      raise IdentityConflict, "Actor URI is not valid for the configured instance"
    end

    def validate_existing!(actor, actor_uri)
      return actor if actor.local? && !actor.tombstoned? && actor.uri == actor_uri &&
        actor.public_key_id == @config.key_id(@user.username)

      unless @config.local_uri?(actor.uri)
        raise IdentityConflict, "Actor #{actor.uri} was created under another FEDERATION_BASE_URL than " \
                                "#{@config.base_url}; move it with bin/rails federation:rename_host FROM=<old base URL>"
      end

      raise IdentityConflict, "Existing actor identity conflicts with the configured user"
    end
  end
end
