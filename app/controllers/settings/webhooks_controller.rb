# frozen_string_literal: true

module Settings
  # Webhooks on « API et webhooks » (DESIGN.md §20.18, PLAN_API.md §11), the
  # same operations as the REST API through `Webhooks::Management`. A secret
  # is shown once, after creation or rotation: the session holds only which
  # endpoint to reveal, never the secret.
  class WebhooksController < ApplicationController
    DELIVERIES_PER_PAGE = 25
    DELIVERY_WINDOW = 30.days

    before_action :set_endpoint, except: %i[new create redeliver]

    rescue_from Webhooks::Management::Inactive do
      redirect_back_or_to settings_api_path, alert: t("settings.webhooks.inactive"), status: :see_other
    end

    def new
      @endpoint = current_user.webhook_endpoints.new(events: [])
    end

    def create
      @endpoint = current_user.webhook_endpoints.new
      if Webhooks::Management.save(@endpoint, **form_values, fields: %i[url description events])
        reveal_secret(@endpoint)
        redirect_to secret_settings_webhook_path(@endpoint), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def show
      scope = @endpoint.deliveries.where(created_at: DELIVERY_WINDOW.ago..).includes(:webhook_event).newest_first
      @page = [ params[:page].to_i, 1 ].max
      @deliveries = scope.offset((@page - 1) * DELIVERIES_PER_PAGE).limit(DELIVERIES_PER_PAGE + 1).to_a
      @next_page = @deliveries.size > DELIVERIES_PER_PAGE
      @deliveries = @deliveries.first(DELIVERIES_PER_PAGE)
      @pending = @deliveries.any?(&:pending?)
      return unless request.headers["Turbo-Frame"] == "webhook-deliveries"

      render partial: "settings/webhooks/deliveries",
             locals: { endpoint: @endpoint, deliveries: @deliveries, page: @page, next_page: @next_page, pending: @pending }
    end

    def edit; end

    def update
      if Webhooks::Management.save(@endpoint, **form_values, fields: %i[url description events])
        redirect_to settings_webhook_path(@endpoint), notice: t(".saved"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      Webhooks::Management.destroy!(@endpoint)
      redirect_to settings_api_path, notice: t(".deleted"), status: :see_other
    end

    # Pauses an active endpoint; resumes a paused one or re-enables one the
    # system disabled.
    def toggle
      Webhooks::Management.save(@endpoint, active: !@endpoint.deliverable?, fields: %i[active])
      redirect_back_or_to settings_api_path, notice: t(".#{@endpoint.deliverable? ? 'enabled' : 'paused'}"),
                                             status: :see_other
    end

    def ping
      Webhooks::Management.ping!(@endpoint)
      redirect_to settings_webhook_path(@endpoint), notice: t(".sent"), status: :see_other
    end

    def rotate_secret
      @endpoint.rotate_secret!
      reveal_secret(@endpoint)
      redirect_to secret_settings_webhook_path(@endpoint), status: :see_other
    end

    def secret
      held = session.delete(:fresh_webhook_secret)
      return redirect_to settings_webhook_path(@endpoint) unless held == @endpoint.id

      response.headers["Cache-Control"] = "no-store"
    end

    def redeliver
      delivery = WebhookDelivery.joins(:webhook_endpoint).where(webhook_endpoints: { user_id: current_user.id })
                                .find_by_short_id!(params[:id])
      Webhooks::Management.redeliver!(delivery)
      redirect_to settings_webhook_path(delivery.webhook_endpoint), notice: t("settings.webhooks.redeliver.sent"),
                                                                    status: :see_other
    end

    private

    def set_endpoint
      @endpoint = current_user.webhook_endpoints.find_by_short_id!(params[:id])
    end

    def form_values
      permitted = params.fetch(:webhook_endpoint, {}).permit(:url, :description, events: [])
      { url: permitted[:url], description: permitted[:description], events: permitted[:events] }
    end

    def reveal_secret(endpoint)
      session[:fresh_webhook_secret] = endpoint.id
    end
  end
end
