# frozen_string_literal: true

require "rails_helper"

# The application-surface half of `User::RESERVED_USERNAMES` is a moving
# target: every new top-level route is a name a member could otherwise take
# first. This guard derives the router's literal first path segments and
# proves each one is either reserved or explicitly ignored.
RSpec.describe "reserved usernames" do
  # Routes that name no account: the health probe, the numeric error pages,
  # the framework's own /rails namespace, and the development-only tooling
  # engine, which no production router carries.
  IGNORED_SEGMENTS = %w[404 410 422 500 up rails devtools].freeze

  # "/privacy-zones" and "/.well-known/webfinger" reach username space as
  # "privacy_zones" and "well_known"; "/@:handle" is a dynamic segment, never
  # a literal name, and is skipped.
  def username_for(segment)
    segment.delete_prefix(".").downcase.gsub(/[^a-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  it "reserves every literal first path segment of the router" do
    segments = Rails.application.routes.routes.filter_map do |route|
      segment = route.path.spec.to_s.sub(%r{\A/}, "").split(%r{[/.(]}, 2).first.to_s
      next if segment.blank? || segment.match?(/[:*]/)

      username = username_for(segment)
      username if username.match?(User::USERNAME_FORMAT)
    end.uniq

    expect(segments - IGNORED_SEGMENTS - User::RESERVED_USERNAMES).to be_empty
  end
end
