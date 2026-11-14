# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Federation::Signature::CanonicalRequest do
  let(:fixture) { YAML.load_file(Rails.root.join("spec/fixtures/federation/signature_headers.yml"), aliases: false).fetch("post_activity") }

  it "matches the pinned wire-level canonical request" do
    headers = {
      host: fixture.fetch("host"),
      date: fixture.fetch("date"),
      digest: fixture.fetch("digest"),
      "content-type" => fixture.fetch("content_type")
    }

    canonical = described_class.new(
      method: fixture.fetch("method"),
      path: fixture.fetch("path"),
      headers:,
      signed_headers: fixture.fetch("signed_headers")
    ).call

    expect(canonical).to eq(fixture.fetch("canonical"))
  end

  it "canonicalizes a GET without inventing a content type" do
    get_fixture = YAML.load_file(Rails.root.join("spec/fixtures/federation/signature_headers.yml"), aliases: false).fetch("get_empty_body")

    canonical = described_class.new(
      method: get_fixture.fetch("method"),
      path: get_fixture.fetch("path"),
      headers: get_fixture.slice("host", "date", "digest"),
      signed_headers: get_fixture.fetch("signed_headers")
    ).call

    expect(canonical).to eq(get_fixture.fetch("canonical"))
  end

  it "requires the core signed headers" do
    expect {
      described_class.new(
        method: "GET",
        path: "/users/demo",
        headers: { host: "remote.example" },
        signed_headers: [ "host" ]
      ).call
    }.to raise_error(ArgumentError)
  end
end
