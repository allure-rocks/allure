# frozen_string_literal: true

# The paired light/dark derived route image contract (DESIGN.md §15.4). The
# record owns both attachments and one generation marker; callers ask for the
# variant matching a theme and always get the other one as a fallback, so a
# themed URL never answers 404 while one variant exists (a card whose variant
# lags behind the page theme still renders).
#
# `route_image_variant` handles owner records. Publications keep their own
# verified attachment references and declare the same predicate on top of
# `sanitized_attachment`; remote records resolve cached blobs by descriptor.
module HasRouteImage
  extend ActiveSupport::Concern

  included do
    has_one_attached :route_image, dependent: :purge_later
    has_one_attached :route_image_dark, dependent: :purge_later
  end

  def route_image_variant(theme)
    requested, fallback = if theme.to_s == "dark"
      [ route_image_dark, route_image ]
    else
      [ route_image, route_image_dark ]
    end
    return requested if requested.attached?
    return fallback if fallback.attached?

    nil
  end
end
