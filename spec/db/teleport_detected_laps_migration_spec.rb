# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261107160000_rebuild_teleport_detected_laps").to_s

RSpec.describe RebuildTeleportDetectedLaps do
  include ActiveJob::TestHelper

  def migrate
    migration = described_class.new
    migration.suppress_messages { migration.migrate(:up) }
  end

  # One recording segment of two points, starting at the given position and
  # ending 140 m north-east of it.
  def add_segment(workout, position, latitude, longitude)
    create(:track_segment, workout:, position:, points: [
      { "t" => 0, "d" => 0.0, "lat" => latitude, "lon" => longitude, "ele" => 100.0 },
      { "t" => 60, "d" => 250.0, "lat" => latitude + 0.001, "lon" => longitude + 0.001, "ele" => 110.0 }
    ])
  end

  it "rebuilds the laps of a recording that resumes far from where it stopped" do
    jumped = create(:workout)
    add_segment(jumped, 0, 45.0, 6.4)
    add_segment(jumped, 1, 45.1, 6.5)

    # A pause: the second segment starts exactly where the first ended.
    paused = create(:workout)
    add_segment(paused, 0, 45.0, 6.4)
    add_segment(paused, 1, 45.001, 6.401)

    single = create(:workout)
    add_segment(single, 0, 45.0, 6.4)

    expect { migrate }.to have_enqueued_job(Laps::RebuildJob).with(jumped).exactly(:once)
  end

  it "does not enqueue anything on a fresh installation or without a discontinuity" do
    expect { migrate }.not_to have_enqueued_job(Laps::RebuildJob)

    paused = create(:workout)
    add_segment(paused, 0, 45.0, 6.4)
    add_segment(paused, 1, 45.001, 6.401)

    expect { migrate }.not_to have_enqueued_job(Laps::RebuildJob)
  end

  it "fails visibly when enqueueing is aborted and can be retried" do
    jumped = create(:workout)
    add_segment(jumped, 0, 45.0, 6.4)
    add_segment(jumped, 1, 45.1, 6.5)
    allow(Laps::RebuildJob).to receive(:perform_later).and_return(nil)

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /retry the migration/)

    allow(Laps::RebuildJob).to receive(:perform_later).and_call_original
    expect { migrate }.to have_enqueued_job(Laps::RebuildJob).with(jumped).exactly(:once)
  end
end
