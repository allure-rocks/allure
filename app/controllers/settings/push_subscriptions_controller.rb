# frozen_string_literal: true

module Settings
  # The push subscription of the current session (docs/dev/PUSH.md), written
  # by the « Sur cet iPhone » card from the companion's bridge answer. JSON
  # only; it never reaches another session's row, and it does not exist
  # while push is unconfigured.
  class PushSubscriptionsController < ApplicationController
    before_action :require_push

    def create
      subscription = PushSubscription.find_or_initialize_by(session: Current.session)
      subscription.assign_attributes(user: current_user, endpoint: params[:endpoint].to_s, p256dh: params[:p256dh].to_s,
                                     auth: params[:auth].to_s, failure_count: 0)
      subscription.hide_content = ActiveModel::Type::Boolean.new.cast(params[:hide_content]) if params.key?(:hide_content)
      PushSubscription.transaction do
        # A device registers a new endpoint each time; a row still holding
        # this one belongs to an earlier registration of this account's. Only
        # the account's own row may be replaced — an endpoint alone is never
        # proof of ownership — and the write rolls back with the transaction,
        # so an invalid registration unbinds nothing.
        PushSubscription.where(user_id: current_user.id,
                               endpoint_digest: PushSubscription.digest(subscription.endpoint.to_s.strip))
          .where.not(session_id: Current.session.id).delete_all
        subscription.save!
      end
      render json: state(subscription), status: :created
    rescue ActiveRecord::RecordInvalid
      fields = subscription.errors.attribute_names.map { |name| name == :endpoint_digest ? :endpoint : name }
      render json: { error: "invalid", fields: }, status: :unprocessable_content
    rescue ActiveRecord::RecordNotUnique
      render json: { error: "invalid", fields: [ "endpoint" ] }, status: :unprocessable_content
    end

    def update
      subscription = Current.session.push_subscription
      return head :not_found unless subscription

      subscription.update!(hide_content: ActiveModel::Type::Boolean.new.cast(params.fetch(:hide_content)))
      render json: state(subscription)
    end

    def destroy
      Current.session.push_subscription&.destroy!
      render json: { status: "off" }
    end

    private

    def require_push
      head :not_found unless Allure::Push::Config.enabled?
    end

    def state(subscription)
      { status: "on", hide_content: subscription.hide_content?, endpoint_digest: subscription.endpoint_digest }
    end
  end
end
