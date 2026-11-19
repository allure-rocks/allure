# frozen_string_literal: true

module Allure
  module Insights
    # The measured sections of one workout, paired with the plan that cut them
    # (docs/dev/AI.md §3.1, §3.3). The plan says where a section starts and what
    # it is; the profile says how it went.
    Course = Data.define(:plan, :result) do
      def mode = plan.mode
      def sections = result.sections
      def pairs = plan.slots.zip(result.sections)
    end
  end
end
