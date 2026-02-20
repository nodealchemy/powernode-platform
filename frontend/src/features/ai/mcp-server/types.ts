export interface McpToken {
  id: string;
  name: string;
  masked_token: string;
  permissions: string[];
  scopes: string | null;
  created_at: string;
  last_used_at: string | null;
  expires_at: string;
  revoked: boolean;
}

export interface McpTokenCreateResponse {
  token: string;
  token_id: string;
  name: string;
  permissions: string[];
  expires_at: string;
  created_at: string;
}

export interface McpSession {
  id: string;
  session_token: string;
  user_name: string;
  user_id: string;
  status: string;
  protocol_version: string;
  client_info: Record<string, unknown>;
  last_activity_at: string | null;
  ip_address: string | null;
  user_agent: string | null;
  expires_at: string | null;
  created_at: string;
}

export interface CreateMcpTokenParams {
  name: string;
  permissions?: string[];
}
