# frozen_string_literal: true

# PLAN_MCP.md §4: how much location an API token may hand an AI assistant
# through the MCP endpoint. Chosen once at creation; existing tokens get none.
class AddMcpGeometryToApiTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :api_tokens, :mcp_geometry, :string, null: false, default: "none"
    add_check_constraint :api_tokens, "mcp_geometry IN ('none', 'filtered', 'raw')", name: "api_tokens_mcp_geometry"
  end
end
