# frozen_string_literal: true

module Settings
  # « Compte » (docs/dev/ACCOUNT.md): the data export and the self-service
  # deletion. Both actions require a recent proof of identity in their own
  # controllers; this page only reads.
  class AccountController < ApplicationController
    before_action :set_no_store

    def show
      @user = current_user
      @export = current_user.account_exports.newest_first.first
      @export_requestable = AccountExport.requestable_for?(current_user)
      @next_export_at = AccountExport.next_request_at(current_user) unless @export_requestable
      @deletable = !current_user.instance_operator?
      return if request.headers["Turbo-Frame"].blank?

      render partial: "settings/account/export", locals: { export: @export, requestable: @export_requestable,
                                                           next_export_at: @next_export_at }, layout: false
    end

    private

    def set_no_store
      response.set_header("Cache-Control", "no-store")
    end
  end
end
