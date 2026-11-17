# frozen_string_literal: true

# The owner's answer to a recurring-route suggestion (docs/dev/SEGMENTS.md):
# dismissing closes it for good, and later repeats of the same circuit join it
# silently. Accepting happens by saving the route from the banner, through
# RoutesController.
class RouteSuggestionsController < ApplicationController
  def dismiss
    suggestion = current_user.route_suggestions.pending.find(params[:id])
    suggestion.update!(status: "dismissed")
    redirect_back_or_to workouts_path, notice: t("route_suggestions.notices.dismissed")
  end
end
