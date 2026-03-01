# frozen_string_literal: true

class AddMcpTokenTypeToUserTokens < ActiveRecord::Migration[8.0]
  def up
    # Drop existing check constraint and re-add with 'mcp' included
    remove_check_constraint :user_tokens, name: "valid_token_type"
    add_check_constraint :user_tokens,
      "token_type IN ('access', 'refresh', 'api_key', '2fa', 'impersonation', 'mcp')",
      name: "valid_token_type"
  end

  def down
    remove_check_constraint :user_tokens, name: "valid_token_type"
    add_check_constraint :user_tokens,
      "token_type IN ('access', 'refresh', 'api_key', '2fa', 'impersonation')",
      name: "valid_token_type"
  end
end
