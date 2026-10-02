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

// IMP-cdda895b07a8 — a stdio MCP server's operator-set sandbox capabilities, as
// McpServersController serializes them (`security`). Console-only until the
// PATCH /mcp_servers/:id/security endpoint.
export interface McpServerSecurity {
  allow_network: boolean;
  allow_extended_commands: boolean;
  egress_allowlist: string[];
}

export interface McpSecurityServer {
  id: string;
  name: string;
  status: string;
  command: string | null;
  security: McpServerSecurity;
}
