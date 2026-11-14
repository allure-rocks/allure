# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Federation HTTP signatures" do
  let(:now) { Time.utc(2026, 8, 26, 12) }
  let(:actor) { create(:actor, :local) }
  let(:body) { '{"id":"https://remote.example/activities/1","type":"Follow"}' }
  let(:path) { "/users/marie/inbox" }
  let(:signer) { Federation::Signature::Signer.new(actor:) }

  def signed_headers(date: now.httpdate, request_body: body, content_type: "application/activity+json")
    signer.call(
      method: "POST",
      path:,
      host: "allure.test:3000",
      body: request_body,
      content_type:,
      date:
    )
  end

  it "signs and verifies the exact request body" do
    headers = signed_headers

    verification = Federation::Signature::Verifier.new(now:).call(
      method: "POST",
      path:,
      headers:,
      body:,
      public_key: actor.public_key_pem
    )

    expect(headers.fetch("Digest")).to eq("SHA-256=WNz/ARABH2+jvSIoxkbUBLvKp4CDwVgGwVUQWdeu62k=")
    expect(verification.key_id).to eq(actor.public_key_id)
    expect(verification.signed_headers).to eq(%w[(request-target) host date digest content-type])
  end

  it "uses the empty-byte digest for a GET" do
    headers = signer.call(
      method: "GET",
      path: "/api/v1/trail/fixture/media/gpx",
      host: "allure.test:3000",
      body: "",
      date: now.httpdate
    )

    expect(headers).not_to have_key("Content-Type")
    expect(headers.fetch("Digest")).to eq("SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=")
  end

  it "rejects a modified body" do
    headers = signed_headers

    expect {
      Federation::Signature::Verifier.new(now:).call(
        method: "POST",
        path:,
        headers:,
        body: "modified",
        public_key: actor.public_key_pem
      )
    }.to raise_error(Federation::Signature::Verifier::InvalidSignature, /digest/)
  end

  it "rejects a stale date" do
    headers = signed_headers(date: (now - 5.minutes - 1.second).httpdate)

    expect {
      Federation::Signature::Verifier.new(now:).call(
        method: "POST",
        path:,
        headers:,
        body:,
        public_key: actor.public_key_pem
      )
    }.to raise_error(Federation::Signature::Verifier::InvalidSignature, /clock-skew/)
  end

  it "accepts both five-minute clock boundaries" do
    [ now - 5.minutes, now + 5.minutes ].each do |date|
      headers = signed_headers(date: date.httpdate)

      expect {
        Federation::Signature::Verifier.new(now:).call(
          method: "POST",
          path:,
          headers:,
          body:,
          public_key: actor.public_key_pem
        )
      }.not_to raise_error
    end
  end

  it "rejects a signature that omits a required signed header" do
    headers = signed_headers
    headers["Signature"] = headers.fetch("Signature").sub("headers=\"(request-target) host date digest content-type\"", "headers=\"(request-target) host date content-type\"")

    expect {
      Federation::Signature::Verifier.new(now:).call(
        method: "POST",
        path:,
        headers:,
        body:,
        public_key: actor.public_key_pem
      )
    }.to raise_error(Federation::Signature::Verifier::InvalidSignature, /required header/)
  end

  it "rejects missing core headers" do
    headers = signed_headers.except("Date")

    expect {
      Federation::Signature::Verifier.new(now:).call(
        method: "POST",
        path:,
        headers:,
        body:,
        public_key: actor.public_key_pem
      )
    }.to raise_error(Federation::Signature::Verifier::InvalidSignature)
  end

  it "signs a withdrawal with a tombstoned actor while its key is retained" do
    actor.tombstone!

    expect(signed_headers.fetch("Signature")).to be_present
  end

  it "refuses to sign once the private key has been retired" do
    actor.tombstone!
    actor.update!(private_key_ciphertext: nil, private_key_retired_at: now)

    expect {
      signed_headers
    }.to raise_error(Federation::Signature::Signer::InvalidActor)
  end
end
