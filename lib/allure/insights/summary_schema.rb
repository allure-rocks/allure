# frozen_string_literal: true

module Allure
  module Insights
    # The answer the model must produce (docs/dev/AI.md §4.3). Deliberately
    # flat: the reference endpoint answered this shape in seconds and stalled on
    # a deeper one. One sentence is a complete answer: a quiet outing is not
    # padded (AI.md §4.1).
    module SummarySchema
      MAX_SENTENCES = 5

      module_function

      def call(max_sentences: MAX_SENTENCES)
        {
          "type" => "object",
          "additionalProperties" => false,
          "required" => %w[title sentences],
          "properties" => {
            "title" => { "type" => "string", "maxLength" => 60 },
            "sentences" => {
              "type" => "array",
              "minItems" => 1,
              "maxItems" => max_sentences.clamp(1, MAX_SENTENCES),
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
