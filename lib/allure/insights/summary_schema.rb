# frozen_string_literal: true

module Allure
  module Insights
    # The answer the model must produce (docs/dev/AI.md §4.3). Deliberately
    # flat: the reference endpoint answered this shape in seconds and stalled on
    # a deeper one.
    module SummarySchema
      module_function

      def call
        {
          "type" => "object",
          "additionalProperties" => false,
          "required" => %w[title sentences],
          "properties" => {
            "title" => { "type" => "string", "maxLength" => 60 },
            "sentences" => {
              "type" => "array",
              "minItems" => 2,
              "maxItems" => 5,
              "items" => {
                "type" => "object",
                "additionalProperties" => false,
                "required" => %w[text fact_ids],
                "properties" => {
                  "text" => { "type" => "string", "maxLength" => 400 },
                  "fact_ids" => { "type" => "array", "minItems" => 1, "items" => { "type" => "string" } }
                }
              }
            }
          }
        }
      end
    end
  end
end
