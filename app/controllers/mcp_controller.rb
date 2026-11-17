# frozen_string_literal: true

# The Model Context Protocol endpoint (docs/dev/MCP.md): a third door onto the
# account's own rooms, behind the REST API's token boundary — Bearer only,
# the same refusals and rate limits. Served stateless: every POST is a whole
# JSON-RPC exchange, so no session is kept and no stream is held open.
class McpController < Api::Rest::V1::BaseController
  require_scope "read", only: :create

  def create
    context = AllureMcp::Context.new(user: current_user, token: Current.api_token)
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      AllureMcp::Server.build(context),
      stateless: true,
      enable_json_response: true,
      serve_subscriptions_listen: false,
      # Rails host authorization already checks Host, and a Bearer token
      # rather than a cookie authenticates, so a rebinding gains nothing.
      dns_rebinding_protection: false
    )
    status, headers, body = transport.handle_request(request)
    headers.each { |name, value| response.headers[name] = value }
    render body: Array(body).join, status:, content_type: headers["content-type"] || "application/json"
  end

  # A stateless server offers no stream to GET and no session to DELETE.
  def method_not_allowed
    response.headers["Allow"] = "POST"
    head :method_not_allowed
  end

  private

  # Every tool reads; a POST here is not a mutation for the rate limit.
  def mutation_request? = false
end
