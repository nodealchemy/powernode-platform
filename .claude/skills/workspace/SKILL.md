# Workspace Chat Operations

Manage Powernode workspace conversations — read, send, create, and administer multi-agent chat workspaces.

## Routing

Determine the intent from the user's message (or the automated daemon trigger) and execute the appropriate operation.

### Incoming Messages (default — no arguments)

When invoked with no arguments or by the SSE daemon:

1. Read the `<workspace-messages>` context injected by the `UserPromptSubmit` hook
2. For each message requiring a response, reply via the `platform.send_message` MCP tool with `conversation_id` and `message` params
3. Always acknowledge — never silently ignore workspace communications
4. Process messages in chronological order
5. After responding, continue with any current work in progress

### Send a Message

When the user wants to send a message to a workspace:

| Tool | Parameters |
|------|-----------|
| `platform.send_message` | `conversation_id` (required), `message` (required) |

- Include `@AgentName` in message text to mention and notify specific agents
- If the user doesn't specify a conversation, use the active conversation from `<workspace-messages>` context or ask

### List Workspaces

| Tool | Parameters |
|------|-----------|
| `platform.list_workspaces` | optional `limit` (default 10) |

Shows workspace conversations the current user participates in.

### Read Message History

| Tool | Parameters |
|------|-----------|
| `platform.list_messages` | `conversation_id`, optional `limit` (default 20, max 100) |

Retrieve recent messages from a workspace conversation.

### Create a Workspace

| Tool | Parameters |
|------|-----------|
| `platform.create_workspace` | `name` (required), optional `agent_ids`, optional `include_concierge` |

Creates a new workspace conversation. The calling MCP client agent is automatically added.

### Invite an Agent

| Tool | Parameters |
|------|-----------|
| `platform.invite_agent` | `conversation_id`, `agent_id` (or `"concierge"` for default concierge) |

Add an agent to an existing workspace conversation.

### Active MCP Sessions

| Tool | Parameters |
|------|-----------|
| `platform.active_sessions` | none |

List active MCP client sessions that can be invited to workspaces.

### Concierge Operations

| Tool | Parameters |
|------|-----------|
| `platform.send_concierge_message` | `message` — sends to concierge, gets AI response |
| `platform.confirm_concierge_action` | `conversation_id`, `action_type`, optional `action_params` |
| `platform.list_conversations` | optional `status`, `limit` — list user's conversations |
| `platform.get_conversation_messages` | `conversation_id`, optional `limit` — get full history |

## Workspace Slash Commands

When a workspace message contains a `/command`, treat it as a **literal Claude Code slash command**. Execute it directly — do not interpret or reinterpret the intent. Pass it through exactly as received.

Examples: `/clear`, `/commit`, `/workspace`, `/powernode`, `/audit`, etc.

Acknowledge the command in the workspace after executing it.

## Response Rules

- **Always reply via `platform.send_message` MCP tool** — never respond in the CLI terminal for workspace communications
- **Mention agents** with `@AgentName` when directing responses to specific team members
- **Questions**: answer directly. **Task requests**: execute and report back with results
- **Errors**: if sending fails, inform the workspace with the error details
- **Context**: when workspace messages reference ongoing CLI work, bridge the context — summarize what you're doing or share results
- **Acknowledgments**: don't reply to simple "thanks" or "great" messages — break the courtesy loop
- **MCP tools still used for**: list_workspaces, list_messages, create_workspace, invite_agent, active_sessions, concierge operations
