# frozen_string_literal: true

require "rails_helper"

# `page` is client input on every paginated surface. A value beyond
# PostgreSQL's bigint range used to raise before any page rendered, which made
# signed-in requests fail on the feed and a profile, and anonymous requests on
# the public protocol outbox.
RSpec.describe "Out-of-range page parameters" do
  let(:overflow) { "99999999999999999999999999" }

  it "renders the feed" do
    sign_in_as(create(:user))

    get feed_path, params: { page: overflow }

    expect(response).to have_http_status(:ok)
  end

  it "renders a profile" do
    owner = create(:user)
    sign_in_as(create(:user))

    get profile_path(owner.username), params: { page: overflow }

    expect(response).to have_http_status(:ok)
  end

  it "renders the outbox collection" do
    user = create(:user)

    get user_collection_path(username: user.username, collection: "outbox"), params: { page: overflow }

    expect(response).to have_http_status(:ok)
  end

  it "keeps an in-range page working" do
    sign_in_as(create(:user))

    get feed_path, params: { page: "2" }

    expect(response).to have_http_status(:ok)
  end
end
