# frozen_string_literal: true

require "rails_helper"

# The federation panel in the administration console (docs/dev/ADMIN.md): the
# former /settings/federation surface, moved and expanded, with every mutation
# audited and the legacy address reduced to a redirect.
RSpec.describe "Admin federation" do
  let(:operator) { create(:user, :with_totp, username: "operator") }
  let(:member) { create(:user) }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    example.run
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  describe "authorization" do
    it "requires authentication" do
      get admin_federation_path

      expect(response).to redirect_to(new_session_path)
    end

    it "answers 404 to a non-operator" do
      sign_in_as(member)

      get admin_federation_path

      expect(response).to have_http_status(:not_found)
    end

    it "does not allow a member to mutate blocks" do
      sign_in_as(member)

      post admin_federation_domain_blocks_path, params: { domain_block: { domain: "blocked.example" } }

      expect(response).to have_http_status(:not_found)
      expect(FederationDomainBlock.count).to eq(0)
      expect(AdminEvent.count).to eq(0)
    end
  end

  describe "panel" do
    before { sign_in_as(operator) }

    it "shows the diagnostics and delivery health to the operator" do
      get admin_federation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings.federation.title"))
      expect(response.body).to include(I18n.t("settings.federation.blocks.domains"))
      expect(response.body).to include(I18n.t("admin.federation.health.title"))
    end

    it "removes the federation entry from the settings shell" do
      get settings_profile_path

      expect(response.body).not_to include('href="/settings/federation"')
      expect(response.body).not_to include('href="/admin/federation"')

      get settings_profile_path
      expect(response.body).not_to include('href="/settings/federation"')
    end
  end

  describe "legacy address" do
    it "redirects the operator to the console" do
      sign_in_as(operator)

      get settings_federation_path

      expect(response).to redirect_to(admin_federation_path)
    end

    it "still answers 404 to a member" do
      sign_in_as(member)

      get settings_federation_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "mutations" do
    before { sign_in_as(operator) }

    it "blocks a domain, withdraws its entitlements, and audits" do
      remote = create(:actor, uri: "https://blocked.example/users/demo")
      note = create(:remote_note, actor: remote, source_domain: "blocked.example")
      entitlement = create(
        :remote_note_recipient,
        remote_note: note,
        recipient_actor: Federation::ActorProvisioner.new(user: operator).call!
      )

      post admin_federation_domain_blocks_path, params: { domain_block: { domain: "blocked.example" } }

      expect(response).to redirect_to(admin_federation_path)
      expect(FederationDomainBlock.exists?(domain: "blocked.example")).to be(true)
      expect(entitlement.reload).to be_withdrawn
      expect(AdminEvent.last).to have_attributes(action: "domain_blocked")
      expect(AdminEvent.last.metadata["domain"]).to eq("blocked.example")
    end

    it "rejects an invalid domain without blocking anything" do
      post admin_federation_domain_blocks_path, params: { domain_block: { domain: "https://bad.example" } }

      expect(response).to redirect_to(admin_federation_path)
      expect(flash[:alert]).to eq(I18n.t("settings.federation.flash.invalid_domain"))
      expect(FederationDomainBlock.count).to eq(0)
      expect(AdminEvent.count).to eq(0)
    end

    it "unblocks a domain and audits" do
      block = create(:federation_domain_block, domain: "blocked.example")

      delete admin_federation_domain_block_path(block)

      expect(response).to redirect_to(admin_federation_path)
      expect(FederationDomainBlock.exists?(block.id)).to be(false)
      expect(AdminEvent.last).to have_attributes(action: "domain_unblocked")
    end

    it "blocks and unblocks an actor" do
      actor_uri = "https://blocked.example/users/demo"

      post admin_federation_actor_blocks_path, params: { actor_block: { actor_uri: } }
      block = FederationActorBlock.find_by!(actor_uri:)

      delete admin_federation_actor_block_path(block)

      expect(FederationActorBlock.exists?(block.id)).to be(false)
      expect(AdminEvent.order(:id).pluck(:action)).to eq(%w[actor_blocked actor_unblocked])
    end

    it "creates and removes a peer policy" do
      post admin_federation_peer_policies_path,
        params: { peer_policy: { domain: "peer.example", capability_profile: "restricted_fetch" } }

      expect(response).to redirect_to(admin_federation_path)
      policy = FederationPeerPolicy.find_by!(domain: "peer.example")
      expect(policy.capability_profile).to eq("restricted_fetch")

      delete admin_federation_peer_policy_path(policy)

      expect(FederationPeerPolicy.exists?(policy.id)).to be(false)
      expect(AdminEvent.order(:id).pluck(:action)).to eq(%w[peer_policy_set peer_policy_removed])
    end

    it "retries failed media and audits" do
      attachment = create(:remote_note_attachment, status: "failed")

      post admin_federation_media_retry_path

      expect(response).to redirect_to(admin_federation_path)
      expect(attachment.reload).to be_pending
      expect(Federation::FetchRemoteNoteAttachmentJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "media_retried")
    end
  end
end
