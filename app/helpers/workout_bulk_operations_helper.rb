# frozen_string_literal: true

module WorkoutBulkOperationsHelper
  OPERATION_STATUS_STYLES = {
    "draft" => [ "bg-secondary-lt", "edit" ],
    "queued" => [ "bg-secondary-lt", "clock" ],
    "processing" => [ "bg-primary-lt", "loader" ],
    "completed" => [ "bg-success-lt", "check" ],
    "failed" => [ "bg-danger-lt", "x" ],
    "cancelled" => [ "bg-secondary-lt", nil ]
  }.freeze

  ITEM_STATUS_STYLES = {
    "queued" => [ "bg-secondary-lt", "clock" ],
    "modified" => [ "bg-success-lt", "check" ],
    "skipped" => [ "bg-warning-lt", "arrow-back-up" ],
    "failed" => [ "bg-danger-lt", "x" ],
    "cancelled" => [ "bg-secondary-lt", nil ]
  }.freeze

  def bulk_operation_status_badge(status)
    bulk_status_badge(status, "workouts.bulk.statuses", OPERATION_STATUS_STYLES)
  end

  def bulk_item_status_badge(status)
    bulk_status_badge(status, "workouts.bulk.item_statuses", ITEM_STATUS_STYLES)
  end

  def bulk_item_failure_label(code)
    t("workouts.bulk.item_failures.#{code}")
  end

  def bulk_operation_title(operation, count)
    t("workouts.bulk.review.titles.#{operation}", count:)
  end

  def bulk_operation_confirm_label(operation, count)
    t("workouts.bulk.review.confirm.#{operation}", count:)
  end

  def bulk_operation_notice_level(status)
    case status.to_s
    when "completed" then "success"
    when "failed" then "danger"
    else "warning"
    end
  end

  # The counter names the operation's own effect: a sport change modifies, a
  # deletion removes.
  def bulk_modified_label(operation)
    t("workouts.bulk.counters.#{operation}.modified")
  end

  private

  def bulk_status_badge(status, scope, styles)
    classes, icon = styles.fetch(status.to_s, [ "bg-secondary-lt", nil ])
    label = t("#{scope}.#{status}")
    return tag.span(label, class: "badge #{classes}") unless icon

    tag.span(class: "badge #{classes}") do
      safe_join([ tag.i(class: "ti ti-#{icon} me-1"), label ])
    end
  end
end
