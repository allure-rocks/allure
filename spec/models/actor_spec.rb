# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actor do
  describe "identity invariants" do
    it "accepts a remote actor without local credentials" do
      actor = build(:actor, uri: "https://remote.example/users/marie")

      expect(actor).to be_valid
      expect(actor).to be_remote
    end

    it "rejects a remote actor with a local user" do
      expect(build(:actor, user: build(:user))).not_to be_valid
    end

    it "rejects a remote actor with a private key" do
      actor = build(:actor, private_key_ciphertext: "private")

      expect(actor).not_to be_valid
    end

    it "requires a tombstone when a local actor has no user" do
      actor = build(:actor, :local)
      actor.user = nil
      actor.tombstoned_at = nil

      expect(actor).not_to be_valid
    end

    it "requires a local actor URI to match its user and instance" do
      actor = build(:actor, :local)
      actor.uri = "https://other.example/users/marie"

      expect(actor).not_to be_valid
    end

    it "keeps actor URIs immutable at the database level" do
      actor = create(:actor)

      expect {
        actor.update_column(:uri, "https://remote.example/users/changed")
      }.to raise_error(ActiveRecord::StatementInvalid, /actor URI is immutable/)
    end
  end

  describe "remote cache" do
    it "is fresh for one hour after a fetch" do
      actor = build(:actor, last_fetched_at: 59.minutes.ago)

      expect(actor).to be_cache_fresh
      expect(actor).not_to be_cache_stale
    end

    it "becomes stale after one hour" do
      actor = build(:actor, last_fetched_at: 1.hour.ago)

      expect(actor).not_to be_cache_fresh
      expect(actor).to be_cache_stale
    end

    it "does not consider a local actor a remote cache entry" do
      actor = build(:actor, :local, last_fetched_at: Time.current)

      expect(actor).not_to be_cache_fresh
    end
  end

  describe "tombstone" do
    it "retains the actor row and private key while detaching the user" do
      actor = create(:actor, :local)
      private_key = actor.private_key_ciphertext

      actor.tombstone!

      expect(actor.reload).to be_tombstoned
      expect(actor.user_id).to be_nil
      expect(actor.private_key_ciphertext).to eq(private_key)
    end

    it "tombstones a local actor before its user is deleted" do
      user = create(:user)
      actor = Federation::ActorProvisioner.new(user: user).call!

      expect { user.destroy! }.not_to raise_error
      expect(actor.reload).to be_tombstoned
      expect(actor.user_id).to be_nil
    end
  end

  describe "serialization" do
    it "does not expose the decrypted private key" do
      actor = create(:actor, :local)

      expect(actor.serializable_hash).not_to have_key("private_key_ciphertext")
      expect(actor.to_json).not_to include(actor.private_key_ciphertext)
    end

    it "stores the private key encrypted at rest" do
      actor = create(:actor, :local)
      raw_value = Actor.connection.select_value(
        Actor.sanitize_sql_array([ "SELECT private_key_ciphertext FROM actors WHERE id = ?", actor.id ])
      )

      expect(raw_value).to be_present
      expect(raw_value).not_to eq(actor.private_key_ciphertext)
    end
  end
end
