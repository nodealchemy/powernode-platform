---
Last Updated: 2026-02-28
Platform Version: 0.3.0
---

# Chat System Architecture

Multi-platform chat system connecting external messaging platforms to Powernode's AI agent infrastructure via real-time WebSocket communication.

## Overview

The chat system bridges external messaging platforms (WhatsApp, Telegram, Discord, Slack, Mattermost) with Powernode's AI agents, providing:

- **Multi-platform support** — Unified chat interface across 5 platforms
- **AI agent routing** — Automatic routing to appropriate AI agents
- **Real-time messaging** — WebSocket-based communication via ActionCable
- **Session management** — Stateful conversations with context windows
- **Content moderation** — Blacklisting, rate limiting, and prompt injection protection
- **A2A integration** — Chat messages bridge to Agent-to-Agent task system

---

## Backend Architecture

### Models (`server/app/models/chat/`)

#### Chat::Channel

Multi-platform messaging channel configuration.

**Platforms:** `whatsapp`, `telegram`, `discord`, `slack`, `mattermost`
**Statuses:** `connected`, `disconnected`, `connecting`, `error`

**Key features:**
- Default AI agent assignment per channel
- Team channel bridging (`ai_team_channel_id`)
- Webhook-based message ingestion with unique tokens
- Rate limiting (configurable per minute, max 1000)
- Platform-specific configuration (stored as JSON)
- Per-channel and account-wide blacklisting
- Vault credential integration for platform API keys
- Real-time status change broadcasting

**Associations:**
```
Channel → Sessions (many)
Channel → Messages (through sessions)
Channel → Blacklists (many)
Channel → DefaultAgent (Ai::Agent)
Channel → TeamChannel (Ai::TeamChannel)
```

#### Chat::Session

Stateful conversation session between a platform user and an AI agent.

**Statuses:** `active`, `idle`, `closed`, `blocked`

**Key features:**
- Context window management (max 50 messages)
- Automatic AI conversation creation on session start
- Agent assignment with handoff tracking
- Human escalation support
- Prompt injection sanitization on inbound messages
- Activity-based status transitions (idle detection)
- A2A task integration

**Session lifecycle:**
1. Platform user sends first message → Session created
2. AI conversation auto-created and linked
3. Default agent assigned from channel config
4. Context window builds as messages flow
5. Agent handoff possible via `transfer_to_agent!`
6. Session auto-idles after inactivity
7. Session closes when conversation ends

**Content sanitization:**
Inbound messages are wrapped in safe delimiters to prevent prompt injection:
```
[USER_MESSAGE_START]
<user content>
[USER_MESSAGE_END]
```
Dangerous patterns (`[SYSTEM]`, `[INSTRUCTION]`, `[IGNORE]`) are stripped.

#### Chat::Message

Individual messages within a session.

**Directions:** `inbound` (from platform user), `outbound` (from AI/system)
**Message types:** `text`, `image`, `audio`, `video`, `document`, `location`, `sticker`
**Delivery statuses:** `pending`, `sent`, `delivered`, `read`, `failed`

**Key features:**
- Automatic sync to linked AI conversation
- Delivery status tracking with timestamps
- Media attachment support
- Voice message transcription
- A2A message format conversion (`to_a2a_message`)
- Platform metadata preservation
- Real-time delivery status broadcasting

**Associations:**
```
Message → Session (belongs_to)
Message → AiMessage (optional, links to Ai::Message)
Message → Attachments (many, Chat::MessageAttachment)
Message → A2aTask (one, Ai::A2aTask)
```

#### Chat::MessageAttachment

Media file attachments on messages.

#### Chat::Blacklist

User blocking with optional expiration.

---

### Controllers (`server/app/controllers/api/v1/chat/`)

| Controller | Actions |
|-----------|---------|
| `ChannelsController` | CRUD + connect, disconnect, test, metrics, platforms, cleanup |
| `SessionsController` | CRUD + transfer, close, messages, active sessions, stats |
| `WebhooksController` | Inbound webhook receiver + platform verification |

**Webhook verification** handles platform-specific handshake protocols:
- **Discord**: PING/PONG verification
- **Slack**: URL challenge verification
- **WhatsApp**: Token verification endpoint

---

### Services (`server/app/services/chat/`)

#### Gateway Service

Stateless, per-request gateway adapter pattern — each inbound webhook is processed through a platform-specific adapter that normalizes the message format.

#### Platform Adapters (`server/app/services/chat/adapters/`)

Platform-specific message handling for each supported messaging platform (WhatsApp, Telegram, Discord, Slack, Mattermost).

---

## Real-Time Communication

### AI Conversation Channel (`AiConversationChannel`)

Primary WebSocket channel for AI conversation streaming.

**Subscription:** `{ conversation_id: <id> }`

**Inbound actions:**
- `send_message` — User sends a message (content required)
- `typing_indicator` — User typing status

**Broadcast events:**

| Event | Description |
|-------|-------------|
| `subscription.confirmed` | Successfully subscribed to conversation |
| `message_created` | New message added to conversation |
| `ai_response_streaming` | AI response being streamed |
| `ai_response_complete` | AI response finished |
| `message_updated` | Message content/metadata changed |
| `ai_response_queued` | AI response job queued |
| `typing_indicator` | User typing status change |
| `error` | Error notification |

**Message serialization:**
The channel translates backend model format to frontend-compatible format:
- `role` → `sender_type` mapping: `user` → `user`, `assistant` → `ai`, `system` → `system`
- Per-message agent attribution (message's agent, then conversation's agent)
- Token/cost metadata inclusion
- Action context from `content_metadata` (concierge actions, mentions)

**Authorization:** Users can only subscribe to conversations they have access to (checked via `can_access?` or account matching).

**AI Response flow:**
1. User sends message via `send_message` action
2. Message persisted to conversation
3. `Ai::ConversationResponseJob` queued for async AI response
4. `ai_response_queued` event transmitted immediately
5. AI response streams via `broadcast_ai_streaming`
6. Completion broadcast via `broadcast_ai_complete`

### Other Channels

| Channel | Purpose |
|---------|---------|
| `AiStreamingChannel` | General AI response streaming |
| `AiAgentExecutionChannel` | Agent execution status updates |
| `AiOrchestrationChannel` | Multi-agent orchestration events |
| `AiWorkflowMonitoringChannel` | Workflow run monitoring |
| `AiWorkflowOrchestrationChannel` | Workflow orchestration events |
| `TeamChannelChannel` | Team chat communication |
| `TeamExecutionChannel` | Team task execution updates |
| `DevopsPipelineChannel` | Pipeline run status updates |
| `GitJobLogsChannel` | Git job log streaming |
| `CodeFactoryChannel` | Code Factory execution events |
| `McpChannel` | MCP tool execution events |
| `MissionChannel` | Mission progress updates |
| `NotificationChannel` | User notification delivery |
| `SubscriptionChannel` | Subscription status changes |
| `CustomerChannel` | Customer-facing events |
| `AnalyticsChannel` | Real-time analytics updates |

---

## Frontend Architecture

### Chat Components (`frontend/src/features/ai/chat/`)

The frontend chat interface is built as part of the AI feature module.

**ChatWindowReducer** manages window state with modes:
- `closed` — Chat hidden
- `floating` — Floating overlay window
- `maximized` — Full-screen chat
- `detached` — Separate browser window

**ConversationSidebar** — Resizable (200–400px) with sections:
- Channels, Workspaces, Pinned, Recent conversations

**ChannelConversationComponent** — Renders 10+ message types including:
- Standard text/media, `task_assignment`, `synthesis`, `escalation`, system messages

**Concierge mode** — AI-driven concierge actions with embedded action context in messages.

**State persistence** — Window position, sidebar state, and section preferences persisted to `localStorage`.

### State Management

Chat state uses a combination of:
- **React Query** — Conversation list, message history fetching (`chatApi`)
- **WebSocket state** — Real-time updates via `useConversationSocket` hook
- **Local context + reducer** — Per-conversation UI state (`ChatWindowReducer`)
- **Optimistic rendering** — Messages rendered immediately with server replacement on confirmation

### WebSocket Integration

**`useConversationSocket`** hook provides:
- WebSocket connection via `WebSocketManager`
- Optimistic message rendering
- Streaming chunk assembly for AI responses
- Typing indicator management

**`WebSocketManager`** (20KB) handles:
- ActionCable connection management
- Automatic reconnection with backoff
- Channel subscription lifecycle
- Message dispatch to React state
- Cross-tab message synchronization (via BroadcastChannel API)

---

## Integration Points

### AI Agent System

- Channels assign default AI agents for auto-response
- Sessions create linked `Ai::Conversation` records
- Messages sync to AI message history
- Agent handoffs tracked with counts

### A2A Protocol

- Chat messages convertible to A2A format (`to_a2a_message`)
- A2A tasks linkable to chat messages and sessions
- Task results can trigger outbound chat messages

### Team Channels

- Chat channels bridgeable to `Ai::TeamChannel`
- Enables team-based conversation routing
- Team members receive chat messages as team communications

---

## Message Flow

### Inbound (Platform → Powernode)

```
Platform Webhook → WebhooksController
  → Validate webhook token
  → Check blacklist
  → Check rate limit
  → Find/create session
  → Create Chat::Message (direction: inbound)
    → Sanitize content
    → Sync to AI conversation
    → Trigger AI agent response
    → Broadcast via ActionCable
```

### Outbound (Powernode → Platform)

```
AI Agent generates response
  → Create Ai::Message in conversation
  → Broadcast via AiConversationChannel
  → Create Chat::Message (direction: outbound)
    → Send via platform adapter
    → Track delivery status
    → Broadcast status updates
```

---

## Security

### Prompt Injection Protection

Inbound messages are sanitized before AI processing:
1. Dangerous control patterns stripped
2. Content wrapped in safe delimiters
3. Original content preserved in `content` field
4. Sanitized version stored in `sanitized_content`

### Rate Limiting

Per-channel rate limiting using Redis-backed counters:
- Configurable `rate_limit_per_minute` (1–1000)
- 1-minute sliding window via Rails cache
- Requests rejected with appropriate error when exceeded

### Blacklisting

Two-tier blacklist system:
- **Channel-level** — Block user on specific channel
- **Account-level** — Block user across all channels
- Optional expiration for temporary bans

### Authentication

- Webhook endpoints authenticated via unique `webhook_token`
- WebSocket connections authenticated via JWT token
- API endpoints use standard bearer token authentication
