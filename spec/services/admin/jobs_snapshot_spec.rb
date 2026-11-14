# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Jobs::Snapshot do
  before { clear_solid_queue! }

  it "groups queue depths and latency" do
    create_ready_job(queue_name: "default")
    create_failed_job(queue_name: "default")
    create_scheduled_job(queue_name: "federation", class_name: "Federation::DeliverJob")

    snapshot = described_class.new.call
    default = snapshot.queues.find { it.name == "default" }
    federation = snapshot.queues.find { it.name == "federation" }

    expect(default.ready).to eq(1)
    expect(default.failed).to eq(1)
    expect(default.latency).to be >= 0
    expect(federation.scheduled).to eq(1)
    expect(federation.ready).to eq(0)
  end

  it "lists a paused queue even when it holds no job" do
    SolidQueue::Pause.create!(queue_name: "route_images")

    row = described_class.new.call.queues.find { it.name == "route_images" }

    expect(row.paused).to be(true)
    expect(row.ready).to eq(0)
  end

  it "returns the latest failures and the next scheduled jobs" do
    3.times { |i| create_failed_job(message: "failure #{i}") }

    snapshot = described_class.new.call

    expect(snapshot.failed_count).to eq(3)
    expect(snapshot.failed_executions.size).to eq(3)
    expect(snapshot.failed_executions.first.message).to eq("failure 2")
    expect(snapshot.processes).to eq([])
  end
end
