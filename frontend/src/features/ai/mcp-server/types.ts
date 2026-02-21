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
