# frozen_string_literal: true

require "rails_helper"

RSpec.describe Following do
  describe ".local_user_ids_followed_by" do
    it "selects the ids of the local accounts the actor follows" do
      follower = create(:local_actor)
      followed = create(:local_actor)
      create(:following, :accepted, follower_actor: follower, followed_actor: followed)

      expect(described_class.local_user_ids_followed_by(follower).pluck("users.id"))
        .to contain_exactly(followed.user_id)
    end

    it "ignores pending and undone relationships" do
      follower = create(:local_actor)
      create(:following, follower_actor: follower, followed_actor: create(:local_actor))
      create(:following, :undone, follower_actor: follower, followed_actor: create(:local_actor))

      expect(described_class.local_user_ids_followed_by(follower)).to be_empty
    end

    it "keeps remote followed actors out" do
      follower = create(:local_actor)
      create(:following, :accepted, follower_actor: follower, followed_actor: create(:actor))

      expect(described_class.local_user_ids_followed_by(follower)).to be_empty
    end

    it "is empty without an actor" do
      expect(described_class.local_user_ids_followed_by(nil)).to be_empty
    end
  end
end
