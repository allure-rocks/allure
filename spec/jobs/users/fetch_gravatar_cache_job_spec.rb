# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::FetchGravatarCacheJob, type: :job do
  include ActiveJob::TestHelper
  let(:user) { create(:user, gravatar_opt_in: true, email_address: "Marie@Example.test") }
  let(:hash) { Digest::MD5.hexdigest("marie@example.test") }
  let(:url) { "https://www.gravatar.com/avatar/#{hash}?s=256&d=404" }

  it "caches the fetched image on the account" do
    stub_request(:get, url).to_return(status: 200, body: "fake-jpeg", headers: { "Content-Type" => "image/jpeg" })

    described_class.perform_now(user.id)

    expect(user.reload.gravatar_cache).to be_attached
  end

  it "attaches nothing when no Gravatar exists" do
    stub_request(:get, url).to_return(status: 404)

    described_class.perform_now(user.id)

    expect(user.reload.gravatar_cache).not_to be_attached
  end

  it "attaches nothing for non-image responses" do
    stub_request(:get, url).to_return(status: 200, body: "<html>", headers: { "Content-Type" => "text/html" })

    described_class.perform_now(user.id)

    expect(user.reload.gravatar_cache).not_to be_attached
  end

  it "does nothing once the account opted out again" do
    user.update!(gravatar_opt_in: false)

    described_class.perform_now(user.id)

    expect(user.reload.gravatar_cache).not_to be_attached
  end

  it "purges the cache on opt-out" do
    stub_request(:get, url).to_return(status: 200, body: "fake-jpeg", headers: { "Content-Type" => "image/jpeg" })
    described_class.perform_now(user.id)
    expect(user.reload.gravatar_cache).to be_attached

    perform_enqueued_jobs do
      user.update!(gravatar_opt_in: false)
    end

    expect(user.reload.gravatar_cache).not_to be_attached
  end
end
