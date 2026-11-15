# frozen_string_literal: true

require "uri"

# The local instance's declared capability for one remote authority. This is
# the only source of a remote actor's capability profile: a peer document may
# never promote itself (docs/dev/FEDERATION.md).
class FederationPeerPolicy < ApplicationRecord
  include FederationDomainFormat

  belongs_to :approved_by, class_name: "User", optional: true

  validates :domain, uniqueness: true
  validates :capability_profile, inclusion: { in: Actor::CAPABILITY_PROFILES }

  after_commit :sync_actor_capabilities

  private

  # Actors are matched by exact authority prefix, not by parsing every remote
  # URI. Removing the policy demotes the peer back to `unknown`.
  def sync_actor_capabilities
    target = destroyed? ? "unknown" : capability_profile
    actors_for_domain.find_each do |actor|
      next if actor.capability_profile == target

      actor.update_column(:capability_profile, target)
    end
  end

  def actors_for_domain
    Actor.remote.where("uri ~ ?", "\\Ahttps?://#{Regexp.escape(domain)}(/|$)")
  end
end
