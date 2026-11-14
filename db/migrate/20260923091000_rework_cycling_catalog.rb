# frozen_string_literal: true

# Reworks the cycling catalog (pre-production, no federation in service):
# `cycling_sport` becomes the generic `cycling` catch-all, `cycling_transport`
# is deleted because the `commute` flag replaces it, and every retained
# representation that still names one of the two slugs is normalised to
# `cycling`.
#
# Snapshot immutability is a core contract; this is its one-time controlled
# exception, exactly like `Workouts::PublicationCleanup` writes the redacted
# representation through the relation. Active publications whose reference
# sport no longer renders would answer 404 otherwise.
class ReworkCyclingCatalog < ActiveRecord::Migration[8.1]
  def up
    execute("UPDATE sports SET slug = 'cycling', label = 'Cycling' WHERE slug = 'cycling_sport'")
    cycling_id = select_value("SELECT id FROM sports WHERE slug = 'cycling'")
    return if cycling_id.nil?

    transport_id = select_value("SELECT id FROM sports WHERE slug = 'cycling_transport'")
    if transport_id
      execute("UPDATE workouts SET commute = true, sport_id = #{cycling_id} WHERE sport_id = #{transport_id}")
      execute("UPDATE segments SET sport_id = #{cycling_id} WHERE sport_id = #{transport_id}")
      execute("UPDATE segment_efforts SET sport_id = #{cycling_id} WHERE sport_id = #{transport_id}")
      execute("UPDATE workout_import_batches SET sport_id = #{cycling_id} WHERE sport_id = #{transport_id}")
      # Derived rows are recomputed from the workouts: delete rather than merge
      # so no fabricated personal best crosses the old sport boundary.
      execute("DELETE FROM records WHERE sport_id = #{transport_id}")
      execute("DELETE FROM best_efforts WHERE sport_id = #{transport_id}")
      execute("DELETE FROM effort_records WHERE sport_id = #{transport_id}")
      execute("DELETE FROM sports WHERE id = #{transport_id}")
    end

    rewrite_representations
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def rewrite_representations
    old_slugs = "('cycling_sport', 'cycling_transport')"
    old_labels = "('Cycling (Sport)', 'Cycling (Transport)')"

    execute <<~SQL.squish
      UPDATE workout_publications
      SET representation = jsonb_set(representation, '{sport_slug}', '"cycling"'), updated_at = NOW()
      WHERE representation->>'sport_slug' IN #{old_slugs}
    SQL
    execute <<~SQL.squish
      UPDATE segment_publications
      SET representation = jsonb_set(representation, '{sport_slug}', '"cycling"'), updated_at = NOW()
      WHERE representation->>'sport_slug' IN #{old_slugs}
    SQL
    execute <<~SQL.squish
      UPDATE remote_segments
      SET representation = jsonb_set(representation, '{sport_slug}', '"cycling"'),
          sport_label = CASE WHEN sport_label IN #{old_labels} THEN 'Cycling' ELSE sport_label END,
          updated_at = NOW()
      WHERE representation->>'sport_slug' IN #{old_slugs}
    SQL
    execute <<~SQL.squish
      UPDATE remote_segments SET sport_label = 'Cycling', updated_at = NOW()
      WHERE sport_label IN #{old_labels}
    SQL
    execute <<~SQL.squish
      UPDATE remote_notes
      SET sport_label = 'Cycling',
          representation = jsonb_set(representation, '{sport_label}', '"Cycling"'),
          updated_at = NOW()
      WHERE sport_label IN #{old_labels}
    SQL
  end
end
