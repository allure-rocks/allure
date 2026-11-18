# frozen_string_literal: true

module Allure
  module Insights
    # One computed, formatted fact (docs/dev/AI.md §3.2). `id` is what a
    # sentence cites and what the verifier resolves; `display` is the value in
    # the member's units and language, which the model may quote verbatim but
    # never recompute.
    Fact = Data.define(:id, :kind, :display, :value, :unit, :direction, :sentiment, :weight, :source)
  end
end
