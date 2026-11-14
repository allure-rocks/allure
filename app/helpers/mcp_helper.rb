# frozen_string_literal: true

# Ready-to-paste MCP client configurations for /settings/api (PLAN_MCP.md §7).
# Client configuration formats are the clients' own, so they are not
# translated; only the surrounding labels are.
module McpHelper
  MCP_CLIENTS = %w[claude_code opencode generic].freeze

  def mcp_endpoint_url = "#{Allure::Federation.config.base_url}/mcp"

  def mcp_client_config(client, secret)
    url = mcp_endpoint_url
    header = "Bearer #{secret}"
    case client
    when "claude_code"
      %(claude mcp add --transport http allure #{url} --header "Authorization: #{header}")
    when "opencode"
      JSON.pretty_generate(
        "$schema" => "https://opencode.ai/config.json",
        "mcp" => { "allure" => { "type" => "remote", "url" => url, "headers" => { "Authorization" => header } } }
      )
    when "generic"
      JSON.pretty_generate("mcpServers" => { "allure" => { "url" => url, "headers" => { "Authorization" => header } } })
    else
      raise ArgumentError, "unknown MCP client #{client}"
    end
  end
end
