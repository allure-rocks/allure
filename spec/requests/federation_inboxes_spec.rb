# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Federation inboxes", type: :request do
  let(:recipient) { create(:local_actor) }
  let(:remote_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:remote_actor) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      public_key_id: "https://remote.example/users/demo#main-key",
      public_key_pem: remote_key.public_key.to_pem
    )
  end
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }
  let(:activity) do
    {
      "id" => "https://remote.example/activities/request-1",
      "type" => "Follow",
      "actor" => remote_actor.uri,
      "object" => recipient.uri
    }
  end
  let(:body) { JSON.generate(activity) }

  def signed_request_headers(path:, request_body: body, key: remote_key)
    values = {
      "Host" => "www.example.com",
      "Date" => Time.now.utc.httpdate,
      "Digest" => "SHA-256=#{Base64.strict_encode64(Digest::SHA256.digest(request_body.b))}",
      "Content-Type" => Allure::Federation::MediaTypes::ACTIVITY_PUB
    }
    signed_headers = %w[(request-target) host date digest content-type]
    canonical = Allure::Federation::Signature::CanonicalRequest.new(
      method: "POST", path:, headers: values, signed_headers:
    ).call
    signature = key.sign(OpenSSL::Digest::SHA256.new, canonical)
    {
      "HTTP_HOST" => values.fetch("Host"),
      "HTTP_DATE" => values.fetch("Date"),
      "HTTP_DIGEST" => values.fetch("Digest"),
      "HTTP_SIGNATURE" => %(keyId="#{remote_actor.public_key_id}",algorithm="rsa-sha256",headers="#{signed_headers.join(" ")}",signature="#{Base64.strict_encode64(signature)}"),
      "CONTENT_TYPE" => values.fetch("Content-Type")
    }
  end

  before do
    allow(actor_resolver).to receive(:resolve).with(remote_actor.uri, persist: false).and_return(remote_actor)
    allow(Federation::ActorResolver).to receive(:new).and_return(actor_resolver)
  end

  it "admits a valid signed activity without a browser session" do
    path = federation_inbox_path(username: recipient.user.username)

    expect {
      post path, params: body, headers: signed_request_headers(path:)
    }.to change(FederationInboxItem, :count).by(1)
      .and have_enqueued_job(Federation::ProcessInboxItemJob)

    expect(response).to have_http_status(:accepted)

    expect(response).to have_http_status(:accepted)
  end

  it "returns 401 and does not admit an invalid signature" do
    path = federation_inbox_path(username: recipient.user.username)
    headers = signed_request_headers(path:).merge("HTTP_SIGNATURE" => "invalid")
    allow(Yabeda.allure.federation_inbox_refusals_total).to receive(:increment)
    allow(Rails.logger).to receive(:warn)

    expect { post path, params: body, headers: }.not_to change(FederationInboxItem, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(Yabeda.allure.federation_inbox_refusals_total).to have_received(:increment).with({ reason: "invalid" })
    expect(Rails.logger).to have_received(:warn).with(/inbox refused invalid \(401\).*actor=#{Regexp.escape(remote_actor.uri)}/)
  end

  # The claimed actor and the parser's quote of the body are the request's
  # own bytes: a line break in either would forge a log line.
  it "logs a refusal on one line whatever the body carries" do
    path = federation_inbox_path(username: recipient.user.username)
    forged_actor = "https://remote.example/users/demo\n[federation] inbox admitted actor=https://victim.example/users/x\e[0m"
    forged_body = JSON.generate(activity.merge("actor" => forged_actor))
    allow(actor_resolver).to receive(:resolve).with(forged_actor, persist: false)
      .and_raise(Federation::ActorResolver::InvalidActor, "actor URI is invalid")
    allow(Rails.logger).to receive(:warn)

    post path, params: forged_body, headers: signed_request_headers(path:, request_body: forged_body)
    expect(response).to have_http_status(:unauthorized)

    post path, params: "\n[federation] forged\n{", headers: signed_request_headers(path:, request_body: "\n[federation] forged\n{")
    expect(response).to have_http_status(:unauthorized)

    expect(Rails.logger).to have_received(:warn).twice do |line|
      expect(line).to match(/\A\[federation\] inbox refused invalid \(401\): /)
      expect(line).not_to match(/[[:cntrl:]]/)
    end
  end

  it "asks the sender to retry when its rotated key cannot be fetched right now" do
    path = federation_inbox_path(username: recipient.user.username)
    remote_actor.update!(public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem)
    allow(actor_resolver).to receive(:resolve).with(remote_actor.uri, refresh: true, persist: false)
      .and_raise(Federation::ActorResolver::Unavailable, "timeout")

    expect { post path, params: body, headers: signed_request_headers(path:) }.not_to change(FederationInboxItem, :count)
    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Retry-After"]).to eq("300")
  end

  # PLAN_M5 §12.2: a request whose signature never verifies is not admitted,
  # so the admission limit never sees it; the signer fetch it causes is
  # bounded on its own.
  context "with forged signatures naming the same actor" do
    let(:forger_key) { OpenSSL::PKey::RSA.generate(2048) }

    around do |example|
      Federation::Safety::ResolutionAttempts.store = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Federation::Safety::ResolutionAttempts.store = nil
    end

    it "fetches the claimed actor once, not once per request" do
      path = federation_shared_inbox_path
      allow(actor_resolver).to receive(:resolve).with(remote_actor.uri, refresh: true, persist: false).and_return(remote_actor)
      statuses = Array.new(20) do |index|
        forged = JSON.generate(activity.merge("id" => "https://remote.example/activities/forged-#{index}"))
        post path, params: forged, headers: signed_request_headers(path:, request_body: forged, key: forger_key)
        response.status
      end

      expect(actor_resolver).to have_received(:resolve).once
      expect(statuses.first).to eq(401)
      expect(statuses.drop(1)).to all(eq(503))
      expect(FederationInboxItem.count).to eq(0)
    end
  end

  it "refuses an address over its request limit before reading the activity" do
    path = federation_shared_inbox_path
    allow(Federation::InboxesController.cache_store).to receive(:increment)
      .and_return(Federation::InboxesController::PER_IP_LIMIT + 1)
    allow(Federation::Inbox::Admission).to receive(:new)

    post path, params: body, headers: signed_request_headers(path:)

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("60")
    expect(Federation::Inbox::Admission).not_to have_received(:new)
  end

  it "returns 404 for an unknown shared-inbox recipient" do
    path = federation_shared_inbox_path
    unknown_body = JSON.generate(activity.merge("object" => "http://allure.test:3000/users/unknown"))

    expect {
      post path, params: unknown_body, headers: signed_request_headers(path:, request_body: unknown_body)
    }.not_to change(FederationInboxItem, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "returns 403 for a blocked actor and persists nothing" do
    path = federation_inbox_path(username: recipient.user.username)
    create(:federation_actor_block, actor_uri: remote_actor.uri)

    expect {
      post path, params: body, headers: signed_request_headers(path:)
    }.not_to change(FederationInboxItem, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "returns 429 with Retry-After when the authority is rate limited" do
    path = federation_inbox_path(username: recipient.user.username)
    create_list(:federation_inbox_item, 60, remote_domain: "remote.example", recipient_actor: recipient)

    expect {
      post path, params: body, headers: signed_request_headers(path:)
    }.not_to change(FederationInboxItem, :count)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"].to_i).to be_between(1, 60)
  end

  # The cap is enforced while reading, so an oversized or endless body can
  # never be buffered whole. The admission check remains as a second guard.
  it "reads at most one byte past the body cap before rejecting an oversized activity" do
    path = federation_shared_inbox_path
    cap = Federation::Inbox::Admission::MAX_BODY_BYTES
    captured = nil
    allow(Federation::Inbox::Admission).to receive(:new).and_wrap_original do |original, **kwargs|
      captured = kwargs[:body]
      original.call(**kwargs)
    end

    post path, params: "a" * (cap + 1),
               headers: { "CONTENT_TYPE" => Allure::Federation::MediaTypes::ACTIVITY_PUB }

    expect(captured.bytesize).to eq(cap + 1)
    expect(response).to have_http_status(:unauthorized)
  end
end
