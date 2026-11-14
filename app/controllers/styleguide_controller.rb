# frozen_string_literal: true

# Component styleguide (DESIGN.md §22, PLAN_M4 Slice 3). Development and test
# only — never production. The deterministic Playwright target for all
# frontend work: every shared component in every variant and state, both
# themes (via the topbar toggle) and both locales (via ?locale=).
class StyleguideController < ApplicationController
  allow_unauthenticated_access
  before_action :resume_session
  before_action :ensure_development_or_test

  def show
    @sports = Sport.catalog_order.to_a
    # Server-side white ratios (spec-backed via Allure::Contrast); surface
    # ratios render live through contrast_controller.js, which recomputes on
    # theme change. DESIGN.md §22 requires both printed.
    @avatar_contrasts = User::AVATAR_PALETTE.to_h do |hex|
      [ hex, Allure::Contrast.ratio(hex, "#ffffff").round(2) ]
    end
  end

  private

  def ensure_development_or_test
    raise ActiveRecord::RecordNotFound unless Rails.env.development? || Rails.env.test?
  end
end
