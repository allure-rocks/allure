# frozen_string_literal: true

# Rendered through config.exceptions_app, so these run inside the normal
# middleware stack and can use the application layout, i18n and helpers.
#
# 410 Gone is the one that matters for federation and the one no theme ships:
# when a local actor is deleted we must keep answering its URI with 410 rather
# than 404. The distinction is load-bearing — remote servers treat 404 as
# "temporarily missing, retry later" and 410 as "permanently gone, stop
# delivering and purge". Returning the wrong one leaves other instances
# redelivering to a dead actor indefinitely.
class ErrorsController < ApplicationController
  allow_unauthenticated_access

  layout "error"

  # Codes are stated explicitly rather than looked up in
  # Rack::Utils::SYMBOL_TO_STATUS_CODE. Rack 3.2 renamed :unprocessable_entity
  # to :unprocessable_content (RFC 9110 retitled 422), so that lookup is a
  # moving target across Rack versions while the numbers never change.
  STATUS_CODES = {
    not_found: 404,
    gone: 410,
    unprocessable_entity: 422,
    unprocessable_content: 422,
    internal_server_error: 500
  }.freeze

  def not_found = render_error(:not_found)
  def gone = render_error(:gone)
  def unprocessable_entity = render_error(:unprocessable_entity)
  alias unprocessable_content unprocessable_entity
  def internal_server_error = render_error(:internal_server_error)

  private

  def render_error(status)
    @status = status
    @code = STATUS_CODES.fetch(status)

    respond_to do |format|
      format.html { render :show, status: @code }
      format.json { render json: { error: t("errors.#{status}.title"), status: @code }, status: @code }
      format.any { head @code }
    end
  end
end
