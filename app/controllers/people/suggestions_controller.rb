# frozen_string_literal: true

module People
  # docs/dev/PEOPLE.md: a dismissed suggestion never returns for this account.
  # The row is owner-scoped; the actor is only a preference key.
  class SuggestionsController < ApplicationController
    def destroy
      actor = Actor.find(params[:id])
      PeopleSuggestionDismissal.find_or_create_by!(user: current_user, actor:)

      redirect_to people_path, notice: t("people.suggestions.dismissed"), status: :see_other
    end
  end
end
