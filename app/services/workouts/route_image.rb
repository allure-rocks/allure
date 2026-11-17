# frozen_string_literal: true

module Workouts
  # The generation of the owner route image render (docs/dev/DERIVATIONS.md). Bump
  # it when the rendered contract changes (style, chevrons, framing, renderer
  # swap); RenderRouteImageJob stamps the version it produced, and the rebuild
  # sweep re-renders only the images whose stored version is older or that were
  # reset to 0 when a re-analysis replaced the geometry.
  #
  # One marker covers the light and the dark variant: the job renders and
  # attaches both together, so a stale version always means a missing or stale
  # pair (DESIGN.md §15.4).
  #
  # Publication images are snapshot media and are deliberately outside this
  # marker: a publication keeps the image rendered at its identity.
  module RouteImage
    VERSION = 8
  end
end
