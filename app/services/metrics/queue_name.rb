# frozen_string_literal: true

module Metrics
  # The queue-name label vocabulary. `queue_name` is a free string on enqueue,
  # so anything outside the application's fixed queue set is folded into
  # "other": the label stays bounded no matter what a job declares
  # (docs/dev/METRICS.md).
  module QueueName
    KNOWN = %w[default federation federation_media remote_imports route_images webhooks photos].freeze
    OTHER = "other"

    module_function

    def normalize(name)
      value = name.to_s
      KNOWN.include?(value) ? value : OTHER
    end
  end
end
