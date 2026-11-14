# frozen_string_literal: true

require "rails_helper"
require "digest"
require "yaml"

RSpec.describe "federation signature fixtures" do
  let(:fixtures) do
    YAML.safe_load(
      Rails.root.join("spec/fixtures/federation/signature_headers.yml").read,
      permitted_classes: [],
      aliases: false
    )
  end

  it "pins the POST body digest and canonical signature input" do
    vector = fixtures.fetch("post_activity")
    digest = vector.fetch("digest").delete_prefix("SHA-256=")

    expect(Digest::SHA256.base64digest(vector.fetch("body"))).to eq(digest)
    expect(vector.fetch("canonical")).to include(
      "(request-target): post /users/marie/inbox",
      "digest: #{vector.fetch("digest")}",
      "content-type: application/activity+json"
    )
  end

  it "pins the empty-body digest used by signed GETs" do
    vector = fixtures.fetch("get_empty_body")

    expect(vector.fetch("digest")).to eq(
      "SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
    )
    expect(vector.fetch("signed_headers")).not_to include("content-type")
  end
end
