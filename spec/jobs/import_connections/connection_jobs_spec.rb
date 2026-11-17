# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Import connection jobs" do
  let(:user) { create(:user) }
  let(:connection) { create(:import_connection, :linked, user:) }
  let(:provider) { RemoteImportHelpers::FakeImportProvider.new(activities:, equipment:) }
  let(:activities) { [] }
  let(:equipment) { [] }
  let(:now) { Time.utc(2026, 10, 9, 12) }

  around { |example| with_remote_import_enabled { example.run } }

  before do
    allow(ImportConnections::Providers).to receive(:for).and_return(provider)
    allow(Workouts::RemoteImportBatchJob).to receive(:perform_later)
  end

  describe ImportConnections::SyncJob do
    let(:activities) do
      [ remote_activity(1, started_at: now - 2.hours), remote_activity(2, started_at: now - 1.hour),
        remote_activity(3, started_at: now - 3.hours, geometry: false), remote_activity(4, started_at: now - 4.hours) ]
    end

    it "lists since the last sync minus a day and queues only what is new" do
      connection.update!(last_synced_at: now - 1.hour)
      create(:workout, user:, import_connection: connection, external_id: "1")
      settled = create(:workout_import_batch, user:, sport: nil, source: "garmin_connect", import_connection: connection)
      create(:workout_import_entry, batch: settled, external_id: "4", status: "skipped", skip_reason: "no_file")

      described_class.perform_now(connection, now:)

      expect(provider.listed_windows.sole).to eq([ now - 25.hours, now ])
      batch = connection.import_batches.where(trigger: "scheduled").sole
      # An indoor activity without a GPS track is queued like any other: it is
      # imported positionlessly (docs/dev/NO-GPS.md).
      expect(batch.entries.order(:position).pluck(:external_id, :status)).to eq([ %w[2 queued], %w[3 queued] ])
      expect(Workouts::RemoteImportBatchJob).to have_received(:perform_later).with(batch)
      expect(connection.reload.last_synced_at).to eq(now)
    end

    it "creates no batch when nothing is new" do
      activities.each { |activity| create(:workout, user:, import_connection: connection, external_id: activity.external_id) }

      expect { described_class.perform_now(connection, now:) }.not_to change(WorkoutImportBatch, :count)
      expect(connection.reload.last_synced_at).to eq(now)
    end

    it "expires the connection and tells the owner when the token is refused" do
      allow(provider).to receive(:list).and_raise(Allure::RemoteImports::Error::AuthError, "401")

      described_class.perform_now(connection, now:)

      expect(connection.reload.status).to eq("expired")
      expect(Notification.where(user:, kind: "import_connection_expired", subject: connection)).to exist
    end

    it "does nothing for a connection without automatic sync" do
      connection.update!(auto_sync: false)

      described_class.perform_now(connection, now:)

      expect(provider.listed_windows).to be_empty
    end

    it "syncs on demand without automatic sync and marks the batch manual" do
      connection.update!(auto_sync: false, last_synced_at: now - 1.hour)

      described_class.perform_now(connection, now:, manual: true)

      expect(provider.listed_windows.sole).to eq([ now - 25.hours, now ])
      batch = connection.import_batches.sole
      expect(batch.trigger).to eq("manual")
      expect(batch.entries.order(:position).pluck(:external_id)).to eq(%w[1 2 3 4])
      expect(Workouts::RemoteImportBatchJob).to have_received(:perform_later).with(batch)
      expect(connection.reload.last_synced_at).to eq(now)
    end
  end

  describe ImportConnections::SyncAllJob do
    it "spreads one sync per linked connection with automatic sync" do
      connection
      create(:import_connection, :linked, auto_sync: false)
      create(:import_connection, :linked, user: create(:user, suspended_at: Time.current))

      expect { described_class.perform_now }.to have_enqueued_job(ImportConnections::SyncJob).with(connection).exactly(:once)
    end
  end

  describe ImportConnections::EquipmentSyncJob do
    let(:equipment) do
      [ Allure::RemoteImports::RemoteEquipment.new(external_id: "g-1", name: "Canyon", kind: "bike", brand: "Canyon",
                                                   model: "Ultimate", active: true),
        Allure::RemoteImports::RemoteEquipment.new(external_id: "g-2", name: "Pegasus", kind: "shoes", brand: nil,
                                                   model: nil, active: false) ]
    end

    it "creates each item once, avoids label collisions and attaches recorded gear" do
      create(:equipment, user:, label: "Canyon")
      workout = create(:workout, user:, import_connection: connection, external_id: "1")
      batch = create(:workout_import_batch, user:, sport: nil, source: "garmin_connect", import_connection: connection)
      create(:workout_import_entry, batch:, workout:, status: "imported", external_id: "1",
                                    metadata: { "equipment_external_id" => "g-1" })

      2.times { described_class.perform_now(connection) }

      bike = connection.equipments.find_by!(external_id: "g-1")
      expect(bike).to have_attributes(label: "Canyon (2)", description: "Canyon Ultimate", is_active: true)
      expect(bike.equipment_type.slug).to eq("bike")
      expect(connection.equipments.find_by!(external_id: "g-2")).to have_attributes(is_active: false)
      expect(connection.equipments.count).to eq(2)
      expect(workout.reload.equipments).to eq([ bike ])
    end
  end

  describe ImportConnections::UnlinkJob do
    let!(:workout) { create(:workout, user:, import_connection: connection, external_id: "1") }
    let!(:item) { create(:equipment, user:, import_connection: connection, external_id: "g-1") }
    let!(:own) { create(:workout, user:) }

    before { connection.update!(status: "unlinking") }

    it "deletes what the connection imported when asked, and wipes the link" do
      described_class.perform_now(connection, delete_data: true)

      expect(Workout.exists?(workout.id)).to be(false)
      expect(Equipment.exists?(item.id)).to be(false)
      expect(Workout.exists?(own.id)).to be(true)
      expect(connection.reload).to have_attributes(status: "unlinked", credentials: {})
      expect(provider.deauthorized).to be(true)
    end

    it "keeps the imported data, still known to the connection" do
      described_class.perform_now(connection, delete_data: false)

      expect(workout.reload).to have_attributes(import_connection: connection, external_id: "1")
      expect(item.reload.import_connection).to eq(connection)
      expect(connection.reload.status).to eq("unlinked")
    end
  end
end
