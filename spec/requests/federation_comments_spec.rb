# frozen_string_literal: true

require "rails_helper"

# The comment object endpoint (docs/dev/COMMENTS.md): a public local comment
# in its thread answers anyone; everything else is 404.
RSpec.describe "Comment objects" do
  let(:owner) { create(:user) }
  let(:reader) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  before { create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(owner)) }

  def fetch(comment_or_id)
    id = comment_or_id.respond_to?(:to_param) ? comment_or_id.to_param : comment_or_id
    get "/api/v1/comment/#{id}", headers: { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB }
  end

  it "serves a public local comment to an unsigned request" do
    comment = Comments::Post.new(user: reader, target: workout, body: "Belle sortie").call!

    fetch(comment)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/activity+json")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(JSON.parse(response.body)).to include("id" => comment.uri, "type" => "Note", "content" => "Belle sortie")
    expect(comment_object_path(comment)).to eq(URI(comment.uri).path)
  end

  it "answers 404 for a withdrawn, a followers, a remote, or an unknown comment" do
    deleted = Comments::Post.new(user: reader, target: workout, body: "Oups").call!.tap(&:mark_deleted!)
    followers = create(:comment, workout:, audience: "followers")
    remote = create(:comment, workout:, actor: create(:actor), uri: "https://remote.example/api/v1/comment/r")

    [ deleted, followers, remote, "unknown" ].each do |target|
      fetch(target)
      expect(response).to have_http_status(:not_found)
    end
  end
end
