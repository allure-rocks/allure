# frozen_string_literal: true

module Segments
  # The generation of the owner segment image render (PLAN_DERIVATIONS.md).
  # Bump it when the rendered contract changes (style, chevrons, framing,
  # renderer swap, smoothing level); Segments::RenderRouteImageJob stamps the
  # version it produced, and the rebuild sweeps re-render only the images whose
  # stored version is older.
  #
  # One marker covers the light and the dark variant: the job renders and
  # attaches both together, so a stale version always means a missing or stale
  # pair (DESIGN.md §15.4).
  #
  # Publication images are snapshot media and are deliberately outside this
  # marker: a course publication keeps the image rendered at its identity.
  module RouteImage
    VERSION = 7
  end
end
