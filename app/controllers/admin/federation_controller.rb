# frozen_string_literal: true

module Admin
  # The federation panel: the former /settings/federation diagnostics and safety
  # controls, now part of the administration console and extended with delivery
  # health. Every mutation is audited (PLAN_ADMIN.md §4.3). The privacy contract
  # is unchanged: counts and identifiers only, never coordinates, payloads,
  # keys, inbox bodies, or remote HTML.
  class FederationController < BaseController
    def show
      @diagnostics = Federation::Diagnostics.new.call
      @delivery_health = FederationHealth.new.call
    end

    def create_domain_block
      block = Federation::Safety::Blocking.new.block_domain!(
        domain: block_domain_params.fetch(:domain), created_by: current_user
      )
      audit(:domain_blocked, domain: block&.domain || block_domain_params[:domain])
      redirect_to admin_federation_path, notice: t("settings.federation.flash.domain_blocked")
    rescue ActiveRecord::RecordInvalid, KeyError
      redirect_to admin_federation_path, alert: t("settings.federation.flash.invalid_domain")
    end

    def destroy_domain_block
      block = FederationDomainBlock.find(params[:id])
      domain = block.domain
      Federation::Safety::Blocking.new.unblock_domain!(domain:)
      audit(:domain_unblocked, domain:)
      redirect_to admin_federation_path, notice: t("settings.federation.flash.domain_unblocked")
    end

    def create_actor_block
      block = Federation::Safety::Blocking.new.block_actor!(
        actor_uri: actor_block_params.fetch(:actor_uri), created_by: current_user
      )
      audit(:actor_blocked, actor_uri: block&.actor_uri || actor_block_params[:actor_uri])
      redirect_to admin_federation_path, notice: t("settings.federation.flash.actor_blocked")
    rescue ActiveRecord::RecordInvalid, KeyError
      redirect_to admin_federation_path, alert: t("settings.federation.flash.invalid_actor")
    end

    def destroy_actor_block
      block = FederationActorBlock.find(params[:id])
      actor_uri = block.actor_uri
      Federation::Safety::Blocking.new.unblock_actor!(actor_uri:)
      audit(:actor_unblocked, actor_uri:)
      redirect_to admin_federation_path, notice: t("settings.federation.flash.actor_unblocked")
    end

    def create_peer_policy
      domain = peer_policy_params.fetch(:domain).to_s.strip.downcase
      policy = FederationPeerPolicy.find_or_initialize_by(domain:)
      policy.capability_profile = peer_policy_params[:capability_profile]
      policy.approved_by = current_user
      policy.save!
      audit(:peer_policy_set, domain:, capability: policy.capability_profile)
      redirect_to admin_federation_path, notice: t("settings.federation.flash.policy_saved")
    rescue ActiveRecord::RecordInvalid, KeyError
      redirect_to admin_federation_path, alert: t("settings.federation.flash.invalid_policy")
    end

    def destroy_peer_policy
      policy = FederationPeerPolicy.find(params[:id])
      domain = policy.domain
      policy.destroy!
      audit(:peer_policy_removed, domain:)
      redirect_to admin_federation_path, notice: t("settings.federation.flash.policy_removed")
    end

    def retry_media
      count = Federation::RemoteMedia::Retry.new.call
      audit(:media_retried, count:)
      redirect_to admin_federation_path, notice: t("settings.federation.flash.media_retried", count:)
    end

    private

    def audit(action, metadata)
      Audit.record(actor: current_user, action:, metadata: metadata.compact)
    end

    def block_domain_params
      params.require(:domain_block).permit(:domain)
    end

    def actor_block_params
      params.require(:actor_block).permit(:actor_uri)
    end

    def peer_policy_params
      params.require(:peer_policy).permit(:domain, :capability_profile)
    end
  end
end
