// Declarative catalog of core AI frontend actions to smoke-test.
//
// Each domain may define:
//   read[]      GET endpoints that need no resource id (lists, stats, catalogs).
//               Always safe — pure reads of pre-existing data.
//   sample      Pull the first record id from `listPath` and exercise its
//               detail/show + read sub-resources. Safe — reads only; skipped
//               when the list is empty.
//   lifecycle   Full create -> exercise -> destroy on a namespaced fixture the
//               harness owns (smoketest-<runId>-*). Only runs in the `write`/
//               `all` phase. NEVER touches pre-existing records.
//
// Action tags:
//   expect: [statuses]   non-2xx statuses that are acceptable for this action.
//   sideEffects:'external'  hits a real LLM / external API (cost + side effect).
//                           Listed for documentation but NOT executed by the
//                           default runner (see run.mjs SKIP_EXTERNAL).
//
// Paths are relative to the API base (default http://localhost:3000/api/v1).
// Bodies mirror the EXACT wrapper key the frontend service sends, e.g.
// providersApi.updateProvider sends { provider: {...} }.

/** @param {string} runId */
export function buildManifest(runId) {
  const stamp = `smoketest-${runId}`;

  return {
    // ---------------------------------------------------------------- providers
    providers: {
      label: 'Providers',
      read: [
        { id: 'list', method: 'GET', path: '/ai/providers' },
        { id: 'statistics', method: 'GET', path: '/ai/providers/statistics' },
        { id: 'available', method: 'GET', path: '/ai/providers/available' },
      ],
      sample: {
        listPath: '/ai/providers',
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/providers/${id}` },
          { id: 'models', method: 'GET', path: `/ai/providers/${id}/models` },
          { id: 'check_availability', method: 'GET', path: `/ai/providers/${id}/check_availability` },
          { id: 'credentials.list', method: 'GET', path: `/ai/providers/${id}/credentials` },
        ],
      },
      lifecycle: {
        create: {
          method: 'POST',
          path: '/ai/providers',
          body: {
            provider: {
              name: `${stamp}-provider`,
              provider_type: 'custom',
              api_base_url: 'https://api.smoketest.invalid/v1',
              api_endpoint: 'https://api.smoketest.invalid/v1/chat/completions',
              capabilities: ['text_generation'],
              supported_models: [{ id: 'smoke-model', name: 'Smoke Model' }],
              configuration_schema: { type: 'object', properties: {} },
              is_active: false,
            },
          },
          idPath: ['provider', 'id'],
        },
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/providers/${id}` },
          // Replays the anchor bug class: a partial PATCH that omits
          // supported_models must still succeed.
          { id: 'update', method: 'PATCH', path: `/ai/providers/${id}`, body: { provider: { description: 'smoke-test edit' } } },
        ],
        destroy: { method: 'DELETE', path: (id) => `/ai/providers/${id}` },
        external: [
          { id: 'test_connection', method: 'POST', path: (id) => `/ai/providers/${id}/test_connection`, sideEffects: 'external' },
          { id: 'sync_models', method: 'POST', path: (id) => `/ai/providers/${id}/sync_models`, sideEffects: 'external' },
        ],
      },
    },

    // ------------------------------------------------------------------- agents
    agents: {
      label: 'Agents',
      read: [
        { id: 'list', method: 'GET', path: '/ai/agents' },
        { id: 'statistics', method: 'GET', path: '/ai/agents/statistics' },
        { id: 'agent_types', method: 'GET', path: '/ai/agents/agent_types' },
        { id: 'my_agents', method: 'GET', path: '/ai/agents/my_agents' },
        { id: 'public_agents', method: 'GET', path: '/ai/agents/public_agents' },
      ],
      sample: {
        listPath: '/ai/agents',
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/agents/${id}` },
          { id: 'stats', method: 'GET', path: `/ai/agents/${id}/stats` },
          { id: 'validate', method: 'GET', path: `/ai/agents/${id}/validate` },
          { id: 'skills', method: 'GET', path: `/ai/agents/${id}/skills` },
          { id: 'conversations', method: 'GET', path: `/ai/agents/${id}/conversations` },
        ],
      },
      lifecycle: {
        // Agents are created inactive (controller forces status) and need no
        // provider, so CRUD is self-contained and safe.
        create: {
          method: 'POST',
          path: '/ai/agents',
          // Agents belong_to a provider (not optional), so reference an existing
          // one resolved at runtime from the providers list.
          body: async ({ firstId }) => ({
            agent: {
              name: `${stamp}-agent`,
              agent_type: 'assistant',
              description: 'AI smoke test agent',
              ai_provider_id: await firstId('/ai/providers'),
            },
          }),
          idPath: ['agent', 'id'],
        },
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/agents/${id}` },
          { id: 'update', method: 'PATCH', path: `/ai/agents/${id}`, body: { agent: { description: 'smoke-test edit' } } },
          { id: 'validate', method: 'GET', path: `/ai/agents/${id}/validate` },
        ],
        destroy: { method: 'DELETE', path: (id) => `/ai/agents/${id}` },
      },
    },

    // -------------------------------------------------------------------- teams
    teams: {
      label: 'Teams',
      read: [
        { id: 'list', method: 'GET', path: '/ai/teams' },
        { id: 'templates', method: 'GET', path: '/ai/teams/templates' },
        { id: 'role_profiles', method: 'GET', path: '/ai/teams/role_profiles' },
        { id: 'trajectories', method: 'GET', path: '/ai/teams/trajectories' },
        { id: 'my_channels', method: 'GET', path: '/ai/channels' },
      ],
      sample: {
        listPath: '/ai/teams',
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/teams/${id}` },
          { id: 'roles', method: 'GET', path: `/ai/teams/${id}/roles` },
          { id: 'channels', method: 'GET', path: `/ai/teams/${id}/channels` },
          { id: 'executions', method: 'GET', path: `/ai/teams/${id}/executions` },
          { id: 'composition_health', method: 'GET', path: `/ai/teams/${id}/composition_health` },
        ],
      },
      lifecycle: {
        // Teams use a top-level body (no wrapper key) and are created inactive.
        create: {
          method: 'POST',
          path: '/ai/teams',
          body: {
            // mesh teams require consensus/auction coordination (cross-field rule)
            name: `${stamp}-team`,
            team_type: 'mesh',
            coordination_strategy: 'consensus',
            status: 'inactive',
            description: 'AI smoke test team',
          },
          idPath: ['id'],
        },
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/teams/${id}` },
          { id: 'update', method: 'PATCH', path: `/ai/teams/${id}`, body: { description: 'smoke-test edit' } },
          { id: 'roles', method: 'GET', path: `/ai/teams/${id}/roles` },
        ],
        destroy: { method: 'DELETE', path: (id) => `/ai/teams/${id}` },
      },
    },

    // ------------------------------------------------------------ conversations
    conversations: {
      label: 'Conversations',
      read: [
        { id: 'list', method: 'GET', path: '/ai/conversations' },
        { id: 'search', method: 'GET', path: '/ai/conversations/search?q=smoke' },
      ],
      sample: {
        listPath: '/ai/conversations',
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/conversations/${id}` },
          { id: 'stats', method: 'GET', path: `/ai/conversations/${id}/stats` },
          { id: 'scheduled_messages', method: 'GET', path: `/ai/conversations/${id}/scheduled_messages` },
        ],
      },
      // No WRITE lifecycle: conversations#create is provider-gated
      // (ProviderAvailabilityService.validate_agent_provider! -> 412 without an
      // active provider + credentials), and update/delete would mutate real
      // records. Covered by READ + SAMPLE only.
    },

    // ------------------------------------------------------------- data_sources
    data_sources: {
      label: 'Data Sources',
      read: [{ id: 'list', method: 'GET', path: '/ai/data_sources' }],
      sample: {
        listPath: '/ai/data_sources',
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/data_sources/${id}` },
          { id: 'quota_status', method: 'GET', path: `/ai/data_sources/${id}/quota_status` },
          { id: 'credentials', method: 'GET', path: `/ai/data_sources/${id}/credentials` },
          { id: 'endpoints', method: 'GET', path: `/ai/data_sources/${id}/endpoints` },
        ],
      },
    },

    // ---------------------------------------------------------------------- rag
    rag: {
      label: 'RAG / Knowledge Bases',
      read: [{ id: 'list', method: 'GET', path: '/ai/rag/knowledge_bases' }],
      sample: {
        listPath: '/ai/rag/knowledge_bases',
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/rag/knowledge_bases/${id}` },
          { id: 'documents', method: 'GET', path: `/ai/rag/knowledge_bases/${id}/documents` },
          { id: 'analytics', method: 'GET', path: `/ai/rag/knowledge_bases/${id}/analytics` },
          { id: 'query_history', method: 'GET', path: `/ai/rag/knowledge_bases/${id}/query_history` },
        ],
      },
    },

    // -------------------------------------------------------------- ralph_loops
    ralph_loops: {
      label: 'Ralph Loops',
      read: [
        { id: 'list', method: 'GET', path: '/ai/ralph_loops' },
        { id: 'statistics', method: 'GET', path: '/ai/ralph_loops/statistics' },
      ],
      sample: {
        listPath: '/ai/ralph_loops',
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/ai/ralph_loops/${id}` },
          { id: 'tasks', method: 'GET', path: `/ai/ralph_loops/${id}/tasks` },
          { id: 'iterations', method: 'GET', path: `/ai/ralph_loops/${id}/iterations` },
          { id: 'progress', method: 'GET', path: `/ai/ralph_loops/${id}/progress` },
          { id: 'learnings', method: 'GET', path: `/ai/ralph_loops/${id}/learnings` },
        ],
      },
    },

    // ------------------------------------------------------------- memory_pools
    memory_pools: {
      label: 'Memory Pools',
      read: [{ id: 'list', method: 'GET', path: '/ai/memory_pools' }],
    },

    // ----------------------------------------------------------------------- mcp
    mcp: {
      label: 'MCP Servers',
      read: [{ id: 'list', method: 'GET', path: '/mcp_servers' }],
      sample: {
        listPath: '/mcp_servers',
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/mcp_servers/${id}` },
          { id: 'tools', method: 'GET', path: `/mcp_servers/${id}/mcp_tools` },
          { id: 'oauth_status', method: 'GET', path: `/mcp_servers/${id}/oauth/status` },
        ],
      },
    },

    // ---------------------------------------------------------------------- chat
    chat: {
      label: 'Chat Channels',
      read: [
        { id: 'channels', method: 'GET', path: '/chat/channels' },
        { id: 'platforms', method: 'GET', path: '/chat/channels/platforms' },
        { id: 'sessions', method: 'GET', path: '/chat/sessions' },
        { id: 'active_sessions', method: 'GET', path: '/chat/sessions/active' },
        { id: 'session_stats', method: 'GET', path: '/chat/sessions/stats' },
      ],
      sample: {
        listPath: '/chat/channels',
        steps: (id) => [
          { id: 'show', method: 'GET', path: `/chat/channels/${id}` },
          { id: 'metrics', method: 'GET', path: `/chat/channels/${id}/metrics` },
          { id: 'sessions', method: 'GET', path: `/chat/channels/${id}/sessions` },
        ],
      },
    },

    // ----------------------------------------------------------------- workspaces
    workspaces: {
      label: 'Workspaces',
      read: [
        { id: 'list', method: 'GET', path: '/ai/workspaces' },
        { id: 'active_sessions', method: 'GET', path: '/ai/workspaces/active_sessions' },
      ],
    },

    // ------------------------------------------------------------------ analytics
    analytics: {
      label: 'Analytics',
      read: [
        { id: 'dashboard', method: 'GET', path: '/ai/analytics/dashboard' },
        { id: 'overview', method: 'GET', path: '/ai/analytics/overview' },
        { id: 'metrics', method: 'GET', path: '/ai/analytics/metrics' },
        { id: 'performance', method: 'GET', path: '/ai/analytics/performance' },
        { id: 'costs', method: 'GET', path: '/ai/analytics/costs' },
        { id: 'usage', method: 'GET', path: '/ai/analytics/usage' },
        { id: 'insights', method: 'GET', path: '/ai/analytics/insights' },
        { id: 'recommendations', method: 'GET', path: '/ai/analytics/recommendations' },
        { id: 'trends', method: 'GET', path: '/ai/analytics/trends' },
        { id: 'reports', method: 'GET', path: '/ai/analytics/reports' },
      ],
    },

    // ------------------------------------------------------------- intelligence
    intelligence: {
      label: 'Intelligence (Learning & Coordination)',
      read: [
        { id: 'learning.evaluation_results', method: 'GET', path: '/ai/learning/evaluation_results?limit=100' },
        { id: 'learning.recommendations', method: 'GET', path: '/ai/learning/recommendations' },
        { id: 'coordination.summary', method: 'GET', path: '/ai/coordination/summary' },
        { id: 'coordination.signals', method: 'GET', path: '/ai/coordination/signals' },
        { id: 'coordination.pressure_fields', method: 'GET', path: '/ai/coordination/pressure_fields' },
        { id: 'coordination.team_events', method: 'GET', path: '/ai/coordination/team_events' },
      ],
    },

    // ----------------------------------------------------------------- ingress
    // System extension: reverse-proxy / service-exposure surface (Path A/E of
    // extensions/system/docs/runbooks/traefik-tcp-exposure-vs-dnat.md).
    //
    // Only `ingress_routes` (a derived, read-only projection over
    // System::AcmeCertificate — no model, no writes) is reachable as a plain
    // REST endpoint the frontend calls directly. The mutating actions this
    // domain is named for — system_expose_service_publicly,
    // system_expose_service_local, system_unexpose_service_local,
    // system_reverse_proxy_compose — are MCP-tool-only
    // (Ai::Tools::SystemIngressTool, dispatched via the JSON-RPC
    // POST /api/v1/mcp/message "tools/call" method, not a REST resource this
    // harness's read/sample/lifecycle shapes can express). They are covered
    // instead by REQUEST-level RSpec specs that drive the real MCP dispatch
    // path end to end:
    // extensions/system/server/spec/requests/api/v1/mcp/system_ingress_tool_spec.rb.
    ingress: {
      label: 'Ingress (System Extension)',
      read: [
        { id: 'ingress_routes', method: 'GET', path: '/system/ingress_routes' },
      ],
    },
  };
}
