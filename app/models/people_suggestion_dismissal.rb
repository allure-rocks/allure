# frozen_string_literal: true

# PLAN_PEOPLE.md §4: one account's permanent dismissal of one suggestion.
# The row is owner-scoped and names the suggested actor; a later suggestion
# pass reads it without touching the relationship itself.
class PeopleSuggestionDismissal < ApplicationRecord
  belongs_to :user
  belongs_to :actor

  validates :actor_id, uniqueness: { scope: :user_id }
end
