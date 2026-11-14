# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::HostRename do
  let(:old_base) { Allure::Federation.config.base_url }
  let(:new_config) { Allure::Federation::Config.new(base_url: "https://app.example", protocol: "https") }
  let(:user) { create(:user, username: "marie") }
  let(:actor) { Federation::ActorProvisioner.new(user:).call! }
  let(:remote) { create(:actor, uri: "https://remote.example/users/demo") }
  let!(:following) do
    create(:following, :accepted, follower_actor: actor, followed_actor: remote, uri: "#{actor.uri}/activities/follow-1")
  end
  let!(:event) do
    create(:federation_outbox_event, actor:, subject_id: actor.id, object_uri: actor.uri,
                                     payload: { "type" => "Follow", "actor" => actor.uri, "object" => remote.uri })
  end

  # The trigger comes from a migration; schema.rb does not carry it.
  before do
    ActiveRecord::Base.connection.execute(<<~SQL)
      CREATE OR REPLACE FUNCTION allure_prevent_actor_uri_change() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.uri IS DISTINCT FROM OLD.uri THEN
          RAISE EXCEPTION 'actor URI is immutable (actors_uri_immutable)';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE OR REPLACE TRIGGER actors_uri_immutable BEFORE UPDATE OF uri ON actors
        FOR EACH ROW EXECUTE FUNCTION allure_prevent_actor_uri_change();
    SQL
  end

  def rename = described_class.new(from: old_base, to: new_config)

  it "counts what it would rewrite and changes nothing on a dry run" do
    counts = rename.call

    expect(counts).to include("actors" => 1, "followings" => 1, "federation_outbox_events" => 1)
    expect(actor.reload.uri).to start_with(old_base)
  end

  it "rewrites local identities, leaves remote ones, and finds nothing the second time" do
    rename.call(apply: true)

    expect(actor.reload.uri).to eq("https://app.example/users/marie")
    expect(actor.public_key_id).to eq("https://app.example/users/marie#main-key")
    expect(actor.handle).to eq("marie@app.example")
    expect(following.reload.uri).to eq("https://app.example/users/marie/activities/follow-1")
    expect(event.reload.payload).to eq("type" => "Follow", "actor" => "https://app.example/users/marie",
                                       "object" => remote.uri)
    expect(remote.reload.uri).to eq("https://remote.example/users/demo")
    expect(rename.call(apply: true).values).to all(eq(0))
  end

  it "keeps the immutability trigger after the rename" do
    rename.call(apply: true)

    expect { actor.update_columns(uri: "https://elsewhere.example/users/marie") }
      .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it "refuses a rename to the base URL already configured" do
    expect { described_class.new(from: new_config.base_url, to: new_config) }.to raise_error(described_class::InvalidRename)
  end
end
