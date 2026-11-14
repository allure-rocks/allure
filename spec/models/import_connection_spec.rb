# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportConnection do
  let(:user) { create(:user) }

  it "keeps one connection per account and provider" do
    create(:import_connection, user:)

    duplicate = build(:import_connection, user:)
    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "constrains the provider, status and region in the database" do
    connection = create(:import_connection, user:)

    expect { connection.update_column(:provider, "komoot") }.to raise_error(ActiveRecord::StatementInvalid)
    expect { connection.update_column(:status, "lost") }.to raise_error(ActiveRecord::StatementInvalid)
    expect { connection.update_column(:region, "eu") }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "imports positioned sessions only by default for a provider with the route filter" do
    expect(create(:import_connection, user:, provider: "withings")).to have_attributes(positioned_only?: true)
    expect(create(:import_connection, user:, provider: "exr")).to have_attributes(positioned_only?: false)
    expect(create(:import_connection, user:)).to have_attributes(positioned_only?: false)
  end

  it "requires an expiry while a link is pending" do
    connection = build(:import_connection, user:, status: "pending")

    expect(connection).not_to be_valid
    expect { connection.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)

    connection.pending_expires_at = 5.minutes.from_now
    expect(connection).to be_valid
    expect(connection.pending_expired?(10.minutes.from_now)).to be(true)
  end

  it "encrypts the credentials as one JSON object" do
    connection = create(:import_connection, :linked, user:)

    stored = ImportConnection.connection.select_value("SELECT credentials FROM import_connections WHERE id = #{connection.id}")
    expect(stored).not_to include("refresh")
    expect(connection.reload.credential(:di_refresh_token)).to eq("refresh")
  end

  it "is usable only while linked and enabled by the operator" do
    connection = create(:import_connection, :linked, user:)

    with_remote_import_enabled(enabled: false) { expect(connection.usable?).to be(false) }
    with_remote_import_enabled { expect(connection.usable?).to be(true) }
    connection.status = "expired"
    with_remote_import_enabled { expect(connection.usable?).to be(false) }
    expect(connection.needs_relink?).to be(true)
  end

  it "survives as a link for kept workouts while the account lives, and goes with it" do
    connection = create(:import_connection, :linked, user:)
    workout = create(:workout, user:, import_connection: connection, external_id: "42")

    expect(workout.reload.import_connection).to eq(connection)
    user.destroy!
    expect(ImportConnection.exists?(connection.id)).to be(false)
  end
end
