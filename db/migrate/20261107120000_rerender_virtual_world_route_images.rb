# frozen_string_literal: true

# Watopia's October 2026 map adds the north-west archipelago the Tour of
# Watopia races start on, and Paris's July 2026 expansion moved and enlarged its
# frame (docs/dev/VIRTUAL-PLATFORMS.md). Both are shipped as new world images, so the
# owner route images drawn on them show the old artwork until they are rendered
# again. Only those two worlds changed, so only their recordings are
# invalidated; the global RouteImage::VERSION stays put and the rest of the
# library is not re-rendered.
#
# The circles are the catalogued anchors and radii, frozen here: a migration
# must keep meaning the same thing when the catalogue moves on.
class RerenderVirtualWorldRouteImages < ActiveRecord::Migration[8.1]
  WATOPIA = { longitude: 166.95501, latitude: -11.68342, radius_m: 12_000 }.freeze
  PARIS = { longitude: 2.343175, latitude: 48.886709, radius_m: 8_000 }.freeze

  # Solid Queue lives in another database. Commit the invalidation before its
  # worker can see the sweep; a failed enqueue leaves the migration unapplied
  # and retrying it is safe. Fresh installs have no recordings to enqueue.
  disable_ddl_transaction!

  def up
    execute <<~SQL
      UPDATE workouts
      SET route_image_version = 0
      WHERE origin = 'import'
        AND start_point IS NOT NULL
        AND sport_id IN (SELECT id FROM sports WHERE virtual)
        AND (
          #{within(WATOPIA)}
          OR #{within(PARIS)}
        )
    SQL

    return unless select_value(<<~SQL)
      SELECT 1 FROM workouts
      WHERE origin = 'import'
        AND start_point IS NOT NULL
        AND sport_id IN (SELECT id FROM sports WHERE virtual)
        AND route_image_version = 0
        AND (
          #{within(WATOPIA)}
          OR #{within(PARIS)}
        )
      LIMIT 1
    SQL

    job = Workouts::BackfillRouteImagesJob.set(priority: BacklogPriority::PRIORITY).perform_later
    unless job && job.successfully_enqueued?
      raise ActiveRecord::MigrationError, "Could not enqueue the route image sweep; retry the migration."
    end
  end

  def down
    # Derived-data reconciliation has no inverse: the images rendered after this
    # migration are the current ones, and the previous artwork is gone.
  end

  private

  def within(circle)
    format(
      "ST_DWithin(start_point, ST_SetSRID(ST_MakePoint(%<longitude>f, %<latitude>f), 4326)::geography, %<radius_m>d)",
      circle
    )
  end
end
