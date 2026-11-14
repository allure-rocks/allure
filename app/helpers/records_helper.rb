# frozen_string_literal: true

module RecordsHelper
  # The name of a classic record type or of a best-effort distance.
  def record_label(record)
    if record.is_a?(EffortRecord)
      t("records.distances.#{record.distance_key}")
    else
      t("records.types.#{record.record_type.downcase}")
    end
  end

  # Formats a stored SI record value in the viewer's unit system.
  def format_record_value(record)
    return format_duration(record.duration_seconds) if record.is_a?(EffortRecord)

    case record.record_type
    when "AP", "BP" then format_pace(record.value, sport: record.sport)
    when "AS", "MS" then format_speed(record.value)
    when "FD" then format_distance(record.value)
    when "HA", "MC" then format_elevation(record.value)
    when "LD" then format_duration(record.value)
    end
  end
end
