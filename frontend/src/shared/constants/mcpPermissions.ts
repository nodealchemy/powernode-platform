/**
 * Every permission that opens some part of AI → Platform → MCP: the route
 * guard and the nav gate. McpServersController reads need mcp.servers.read;
 * McpAppsController and Mcp::SessionsController need ai.agents.read. It lives
 * in shared so the navigation config does not depend on the page.
 */
export const MCP_PERMISSIONS: string[] = ['mcp.servers.read', 'ai.agents.read'];
