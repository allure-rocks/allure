# frozen_string_literal: true

class FundingController < ApplicationController
  before_action :require_funding

  def show
    @live_subscriptions = current_user.funding_subscriptions.live.order(created_at: :desc)
    @badge_expires_at = current_user.active_funding_contributions.maximum(:expires_at)
    @checkouts = @live_subscriptions.any? ? {} : checkout_options
    @automatic_flow = @checkouts.values.any? { |checkout| checkout[:automatic] }
    @manual_flow = @checkouts.values.any? { |checkout| !checkout[:automatic] }
  end

  def thanks; end

  def portal
    subscription = current_user.funding_subscriptions.live.find(params[:subscription_id])
    provider = Allure::Funding::Providers.fetch(subscription.provider)
    return head :not_found unless provider

    url = provider.portal_url(subscription:, return_url: funding_url)
    # `redirect_to` logs external locations. A portal URL is short-lived and
    # must not be retained or logged, so answer with the Location header only.
    head :found, location: url
  rescue Allure::Funding::Providers::ProviderError
    redirect_to funding_path, alert: t("funding.manage.portal_unavailable")
  end

  private

  def checkout_options
    providers = Allure::Funding::Providers.enabled
    Allure::Funding::TIERS.each_with_object({}) do |tier, options|
      providers.each do |provider|
        reference = Funding::Reference.generate(user: current_user, tier:)
        url = provider.checkout_url(tier:, reference:)
        next unless url

        options[tier] = { url:, automatic: true }
        break
      end
      next if options[tier]

      if (url = Allure::Funding.checkout_link(tier))
        options[tier] = { url:, automatic: false }
      end
    end
  end

  def require_funding
    head :not_found unless Allure::Funding.enabled? && !helpers.hotwire_native_app?
  end
end
