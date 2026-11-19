# frozen_string_literal: true

module Allure
  # The assistant's facts and their wording (docs/dev/AI.md): Ruby computes and
  # formats every fact, and a local model only puts them into words.
  module Insights
    # Bumped when the prompt, the schema or the fact selection changes. A
    # summary generated under another version is stale (AI.md §5).
    VERSION = 3
  end
end
