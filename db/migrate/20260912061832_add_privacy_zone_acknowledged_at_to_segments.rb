class AddPrivacyZoneAcknowledgedAtToSegments < ActiveRecord::Migration[8.1]
  def change
    # Consent record for sharing a course whose corridor intersects an active
    # privacy zone (docs/dev/SEGMENTS-FEDERATION.md). Zones are not subtracted
    # from a segment; this acknowledges the deliberate exposure.
    add_column :segments, :privacy_zone_acknowledged_at, :datetime
  end
end
