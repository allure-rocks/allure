# frozen_string_literal: true

module Settings
  # Creating and revoking API tokens (docs/dev/API.md). Creation follows a
  # recent proof of identity; the secret is shown once, on the page that
  # follows, and never again.
  class ApiTokensController < ApplicationController
    before_action :require_recent_authentication, only: %i[new create]

    def new
      @token = current_user.api_tokens.new(scopes: [], mcp_geometry: "none")
      @expires_in_days = ApiToken::DEFAULT_EXPIRY_DAYS
    end

    def create
      attributes = token_params
      @token, secret = ApiTokens::Lifecycle.issue!(user: current_user, name: attributes[:name],
                                                   scopes: attributes[:scopes], expires_in_days: attributes[:expires_in_days],
                                                   mcp_geometry: attributes[:mcp_geometry])
      session[:fresh_api_token] = { "user_id" => current_user.id, "token_id" => @token.id, "secret" => secret }
      redirect_to created_settings_api_tokens_path, status: :see_other
    rescue ActiveRecord::RecordInvalid => error
      @token = error.record
      @expires_in_days = attributes[:expires_in_days].to_i
      render :new, status: :unprocessable_content
    end

    def created
      held = session.delete(:fresh_api_token)
      @token = current_user.api_tokens.find_by(id: held["token_id"]) if held.is_a?(Hash) && held["user_id"] == current_user.id
      return redirect_to settings_api_path if @token.nil?

      @secret = held["secret"]
      response.headers["Cache-Control"] = "no-store"
    end

    def destroy
      token = current_user.api_tokens.find_by_short_id!(params[:id])
      ApiTokens::Lifecycle.revoke!(token, by: "owner")
      redirect_to settings_api_path, notice: t(".revoked", name: token.name), status: :see_other
    end

    private

    def token_params
      permitted = params.fetch(:api_token, {}).permit(:name, :expires_in_days, :mcp_geometry, scopes: [])
      { name: permitted[:name].to_s, scopes: Array(permitted[:scopes]).compact_blank,
        expires_in_days: permitted[:expires_in_days].to_i, mcp_geometry: permitted[:mcp_geometry].presence || "none" }
    end
  end
end
