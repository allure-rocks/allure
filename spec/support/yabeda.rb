# frozen_string_literal: true

# Yabeda metrics are process-global: counters and gauges accumulate across
# examples unless reset. Every example starts from an empty metric set and a
# cold snapshot cache, so assertions never depend on example order.
module YabedaHelpers
  def reset_yabeda!
    Yabeda.metrics.each_value do |metric|
      metric.values.clear if metric.respond_to?(:values)
    end
    Metrics::Cache.reset!
  end

  def metric_value(metric, labels = {})
    Yabeda.allure.public_send(metric).get(labels)
  end
end

RSpec.configure do |config|
  config.include YabedaHelpers
  config.before { reset_yabeda! }
end
