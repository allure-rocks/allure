# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261029090000_add_renamed_at_to_segments").to_s

RSpec.describe AddRenamedAtToSegments do
  include ActiveJob::TestHelper

  def migrate
    migration = described_class.new
    migration.suppress_messages { migration.migrate(:up) }
  end

  it "adds a nullable rename mark without guessing existing names and queues nothing" do
    loop_segment = create(:segment, :loop, name: "Tour du lac")

    expect { migrate }.not_to have_enqueued_job(Segments::BackfillLoopReuseJob)

    expect(loop_segment.reload.renamed_at).to be_nil
    expect(loop_segment).not_to be_renamed
  end
end
