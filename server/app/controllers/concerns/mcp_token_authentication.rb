# frozen_string_literal: true

# Triple-mode authentication for MCP Streamable HTTP endpoints.
# Supports (in priority order):
#   1. Per-user MCP token (UserToken type=mcp) — database-backed, scoped permissions
#   2. Static MCP token via POWERNODE_MCP_TOKEN env var (for quick setup / single-user)
#   3. JWT fallback via the existing Authentication concern (for browser/API clients)
module McpTokenAuthentication
  extend ActiveSupport::Concern

  private

  def authenticate_mcp_request
    token = extract_bearer_token

    # Priority 1: Per-user MCP token (strip pnmcp_ prefix if present)
    if token.present?
      raw_token = token.delete_prefix("pnmcp_")
      user_token = UserToken.find_by_token(raw_token)

      if user_token&.token_type == "mcp"
        authenticate_via_user_token(user_token)
        return
      end
    end

    # Priority 2: Static env token — only if bearer token matches the env var
    if static_mcp_token_present? && token.present? &&
       ActiveSupport::SecurityUtils.secure_compare(token, ENV["POWERNODE_MCP_TOKEN"])
      resolve_mcp_user
      return
    end

    # Priority 3: JWT fallback
    authenticate_via_jwt
  end

  def authenticate_via_user_token(user_token)
    user = user_token.user
    if user&.active? && user.account&.active?
      @current_user = user
      @current_account = user.account
      @mcp_token = user_token
      user_token.touch_last_used!(ip: request.remote_ip, user_agent: request.user_agent)
    else
      render_jsonrpc_error(nil, -32001, "User or account inactive")
    end
  end

  def static_mcp_token_present?
    ENV["POWERNODE_MCP_TOKEN"].present?
  end

  def authenticate_via_jwt
    # Delegate to the standard Authentication concern
    authenticate_request
  end

  def resolve_mcp_user
    email = ENV["POWERNODE_MCP_USER_EMAIL"]

    if email.present?
      user = User.includes(:account).find_by(email: email)
      if user&.active? && user.account&.active?
        @current_user = user
        @current_account = user.account
        return
      end
    end

    # Fallback: first active user (core single-user mode)
    user = User.includes(:account).where(status: "active").order(:created_at).first
    if user&.account&.active?
      @current_user = user
      @current_account = user.account
    else
      render_jsonrpc_error(nil, -32001, "No active user found for MCP authentication")
    end
  end

  def extract_bearer_token
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")

    header.split(" ", 2).last
  end
end
