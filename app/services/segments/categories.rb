# frozen_string_literal: true

module Segments
  # The category view of a board (docs/dev/SEGMENTS.md): a filter over the
  # ranking the viewer already reads, never a second eligibility rule. It runs
  # on the loaded rows — best effort per athlete, `user` included — so the
  # board, its rank and the « Mon rang » tile share one rule and one query.
  #
  # A category is offered on a ranking only from MIN_ATHLETES distinct
  # athletes of that category among the rows the viewer sees: below that, the
  # filter would point at one or two people even under an alias.
  module Categories
    module_function

    FILTERS = %w[women men].freeze
    MIN_ATHLETES = 3

    def filter?(value) = FILTERS.include?(value)

    def partition(efforts, category)
      efforts.select { |effort| effort.user.leaderboard_category == category }
    end

    def offered?(efforts, category) = !ranking(efforts, category).nil?

    # The filtered ranking, or nil while the category stays below the
    # threshold on this ranking.
    def ranking(efforts, category)
      rows = partition(efforts, category)
      rows.map(&:user_id).uniq.size >= MIN_ATHLETES ? rows : nil
    end
  end
end
