// Core entity registry — wires the already-built CORE entity-reference infra
// (`@/shared/services/entityRegistry`) to Phase-A high-value core object types.
//
// The registry is owner-keyed (mirrors `featureRegistry`): core registers its
// own types under the "core" owner, exactly as the system extension registers
// under "system" (see extensions/system/.../features/system/entityRegistry.ts).
// `<EntityLink>` / `<EntityReferenceHost>` (mounted once in DashboardLayout)
// then resolve a `type` and render one of three modes:
//
//   1. legacy modal — `legacyParam`                          → opens a pre-existing
//        global modal driven by its OWN url param (?agent=/?team=/?mission=).
//        Takes precedence; no `component`/`fetchById` needed.
//   2. id modal     — `component` + `idProp`                 → bespoke modal self-fetches
//   3. object modal — `component` + `objectProp` + `fetchById`→ host fetches, passes object
//   4. generic      — `fetchById` only                       → field-driven EntityDetailModal
//
// Phase A registers (1) legacy modals for agent/team/mission (reuse the rich
// existing modals) and (4) generic field modals for ~20 read-only types.
//
// Every registered type traces to a VERIFIED `*Api` read method and a permission
// confirmed against the backend controller's `show`/`validate_permissions`.
// Entries whose getById does not exist, or where the only read endpoint needs a
// composite id a caller cannot supply, are intentionally omitted — `EntityLink`
// degrades to plain text for unknown types, so omission is always safe
// (see the OMISSIONS note at the bottom).
import { entityRegistry } from '@/shared/services/entityRegistry';

// Read APIs (generic mode). Each method below is verified to exist with the
// signature used here. The AI-service objects all re-export from the barrel.
import {
  providersApi,
  conversationsApi,
  chatChannelsApi,
  ragApi,
  dataSourcesApi,
  ralphLoopsApi,
  workspacesApi,
  devopsApi,
  containerExecutionApi,
  agentCardsApiService,
  memoryApiService,
  communityAgentsApi,
  governanceApi,
} from '@/shared/services/ai';
import { mcpApi } from '@/shared/services/ai/McpApiService';
import { skillsApi } from '@/features/ai/skills/services/skillsApi';
import { usersApi } from '@/features/account/users/services/usersApi';
import { missionsApi } from '@/features/missions/api/missionsApi';
import { pagesApi } from '@/features/content/pages/services/pagesApi';
import { accountsApi } from '@/features/account/services/accountsApi';
import { rolesApi } from '@/features/admin/roles/services/rolesApi';
import { knowledgeBaseApi } from '@/shared/services/content/knowledgeBaseApi';
import { executionTracesApi } from '@/features/ai/debugging/services/executionTracesApi';
import { getAguiSession } from '@/features/ai/agui/api/aguiApi';
import { swarmApi } from '@/features/devops/swarm/services/swarmApi';
import { codeFactoryApi } from '@/features/ai/code-factory/api/codeFactoryApi';

/**
 * Split a composite EntityLink id (e.g. "knowledgeBaseId:documentId") into its
 * parts. Returns a rejected promise when the id is malformed so the fetch fails
 * loudly rather than issuing a request with empty path segments. Mirrors the
 * system extension's `splitCompositeId` helper.
 */
function requireCompositeId(id: string, parts: number, shape: string): string[] {
  const segments = id.split(':');
  if (segments.length !== parts || segments.some((s) => s.length === 0)) {
    throw new Error(`id must be "${shape}" (got "${id}")`);
  }
  return segments;
}

/**
 * Register every Phase-A core object type with the core entity registry.
 * Idempotent at the call site (re-registration overwrites by type); called once
 * at app startup before the router renders.
 */
export function registerCoreEntities(): void {
  entityRegistry.registerEntities('core', [
    // ================================================================
    // Mode 1: legacy modals (reuse the rich existing global modals).
    // These are mounted in DashboardLayout and read their own url param.
    // No component/fetchById — `legacyParam` takes precedence.
    // ================================================================
    {
      type: 'agent',
      label: 'Agent',
      permission: 'ai.agents.read',
      icon: 'Bot',
      legacyParam: 'agent',
    },
    {
      // Alias: backend polymorphic refs surface as "Ai::Agent"/"AiAgent".
      type: 'ai_agent',
      label: 'Agent',
      permission: 'ai.agents.read',
      icon: 'Bot',
      legacyParam: 'agent',
    },
    {
      // The team detail modal fetches via `teamsApi.getTeam` → GET /ai/teams/:id
      // → TeamsController#show, which is authenticated-only (no resource read
      // permission; `ai.teams.read` does not exist). Gate on auth only so the
      // link stays clickable.
      type: 'agent_team',
      label: 'Team',
      icon: 'Users',
      legacyParam: 'team',
    },
    {
      // Alias for the same legacy modal.
      type: 'team',
      label: 'Team',
      icon: 'Users',
      legacyParam: 'team',
    },
    {
      type: 'mission',
      label: 'Mission',
      permission: 'ai.missions.read',
      icon: 'Target',
      legacyParam: 'mission',
    },

    // ================================================================
    // Mode 4: generic field-driven modal (fetchById only). The generic
    // modal renders the fetched object's top-level scalar fields, so
    // wrapped responses are unwrapped to the underlying record.
    // ================================================================
    {
      // getProvider already unwraps to AiProvider.
      type: 'ai_provider',
      label: 'Provider',
      permission: 'ai.providers.read',
      icon: 'Cloud',
      labelField: 'name',
      fetchById: (id: string) => providersApi.getProvider(id),
    },
    {
      // SkillResponse is `{ success, data?: { skill } }` — unwrap to the skill.
      type: 'skill',
      label: 'Skill',
      permission: 'ai.skills.read',
      icon: 'Sparkles',
      labelField: 'name',
      fetchById: (id: string) => skillsApi.getSkill(id).then((r) => r.data?.skill),
    },
    {
      // UserResponse is `{ success, data: User }` — unwrap to the user. The show
      // action lets a user read themselves; reading an arbitrary referenced user
      // requires `users.read` (enforced in-action), so gate on that.
      type: 'user',
      label: 'User',
      permission: 'users.read',
      icon: 'User',
      labelField: 'name',
      fetchById: (id: string) => usersApi.getUser(id).then((r) => r.data),
    },
    {
      // getConversation already unwraps to ConversationDetail.
      type: 'conversation',
      label: 'Conversation',
      permission: 'ai.conversations.read',
      icon: 'MessageSquare',
      labelField: 'name',
      fetchById: (id: string) => conversationsApi.getConversation(id),
    },
    {
      // GET /chat/channels/:id → ChannelsController#show: authenticated-only,
      // no permission gate. Unwrap `{ channel }`.
      type: 'chat_channel',
      label: 'Chat Channel',
      icon: 'Hash',
      labelField: 'name',
      fetchById: (id: string) => chatChannelsApi.getChannel(id).then((r) => r.channel),
    },
    {
      // GET /ai/rag/knowledge_bases/:id → RagController: authenticated-only.
      type: 'knowledge_base',
      label: 'Knowledge Base',
      icon: 'Library',
      labelField: 'name',
      fetchById: (id: string) => ragApi.getKnowledgeBase(id),
    },
    {
      // A RAG document is addressed only under its knowledge base, so the
      // EntityLink id must be composite "knowledgeBaseId:documentId". Reads are
      // authenticated-only (RagController).
      type: 'knowledge_node',
      label: 'Document',
      icon: 'FileText',
      labelField: 'name',
      fetchById: (id: string) => {
        const [kbId, docId] = requireCompositeId(id, 2, 'knowledgeBaseId:documentId');
        return ragApi.getDocument(kbId, docId);
      },
    },
    {
      // Same backing fetch as knowledge_node — shared knowledge surfaces as a
      // RAG document; composite "knowledgeBaseId:documentId" id.
      type: 'shared_knowledge',
      label: 'Shared Knowledge',
      icon: 'BookOpen',
      labelField: 'name',
      fetchById: (id: string) => {
        const [kbId, docId] = requireCompositeId(id, 2, 'knowledgeBaseId:documentId');
        return ragApi.getDocument(kbId, docId);
      },
    },
    {
      // getServer returns `{ server, tools, ... }` — unwrap to the server row.
      type: 'mcp_server',
      label: 'MCP Server',
      permission: 'mcp.servers.read',
      icon: 'Plug',
      labelField: 'name',
      fetchById: (id: string) => mcpApi.getServer(id).then((r) => r.server),
    },
    {
      // A tool is addressed under its server, so the id must be composite
      // "serverId:toolId". getTool returns `{ tool }` — unwrap.
      type: 'mcp_tool',
      label: 'MCP Tool',
      permission: 'mcp.tools.read',
      icon: 'Wrench',
      labelField: 'name',
      fetchById: (id: string) => {
        const [serverId, toolId] = requireCompositeId(id, 2, 'serverId:toolId');
        return mcpApi.getTool(serverId, toolId).then((r) => r.tool);
      },
    },
    {
      // getDataSource already unwraps to AiDataSource.
      type: 'data_source',
      label: 'Data Source',
      permission: 'ai.data_sources.read',
      icon: 'Database',
      labelField: 'name',
      fetchById: (id: string) => dataSourcesApi.getDataSource(id),
    },
    {
      // getLoop returns `{ ralph_loop }` — unwrap. Reads are gated by
      // `ai.loops.read` (RalphLoopsController#validate_permissions).
      type: 'ralph_loop',
      label: 'Ralph Loop',
      permission: 'ai.loops.read',
      icon: 'RefreshCw',
      labelField: 'name',
      fetchById: (id: string) => ralphLoopsApi.getLoop(id).then((r) => r.ralph_loop),
    },
    {
      // getWorkspace returns `{ workspace, members }` — unwrap to the workspace.
      // WorkspacesController gates every action on `ai.conversations.create`.
      type: 'workspace',
      label: 'Workspace',
      permission: 'ai.conversations.create',
      icon: 'LayoutGrid',
      labelField: 'title',
      fetchById: (id: string) => workspacesApi.getWorkspace(id).then((r) => r.workspace),
    },
    {
      // getTemplate returns `{ template }` — unwrap. DevopsController#show_template
      // is gated by `ai.devops.read`.
      type: 'devops_pipeline',
      label: 'DevOps Template',
      permission: 'ai.devops.read',
      icon: 'GitBranch',
      labelField: 'name',
      fetchById: (id: string) => devopsApi.getTemplate(id).then((r) => r.template),
    },
    {
      // getExecution returns `{ execution }` — unwrap. DevopsExecutionsController
      // #show_execution is gated by `ai.devops.read`. No `name` field; `status`
      // is the most descriptive scalar label.
      type: 'devops_pipeline_run',
      label: 'DevOps Execution',
      permission: 'ai.devops.read',
      icon: 'PlayCircle',
      labelField: 'status',
      fetchById: (id: string) => devopsApi.getExecution(id).then((r) => r.execution),
    },
    {
      // getContainer returns `{ instance }` — unwrap. ContainersController#show
      // is authenticated-only (no permission gate). `template_name` is the
      // friendliest label.
      type: 'docker_container',
      label: 'Container',
      icon: 'Box',
      labelField: 'template_name',
      fetchById: (id: string) => containerExecutionApi.getContainer(id).then((r) => r.instance),
    },
    {
      // getAgentCard returns `{ agent_card }` — unwrap. AgentCardsController
      // gates show on `ai.agents.read`.
      type: 'agent_card',
      label: 'Agent Card',
      permission: 'ai.agents.read',
      icon: 'IdCard',
      labelField: 'name',
      fetchById: (id: string) => agentCardsApiService.getAgentCard(id).then((r) => r.agent_card),
    },
    {
      // getFederationPartner returns `{ partner: FederationPartner }` — unwrap to
      // the partner row. FederationController#show is gated by `ai.federation.read`
      // (FederationController#validate_permissions). The TS `FederationPartner`
      // type declares `federation_key`/`mtls_certificate`, but the backend `show`
      // serializer (`partner_details`) never emits `federation_key` and explicitly
      // `.except`s `mtls_certificate`/`ca_cert`, so the generic modal renders no
      // secret material. Backend `partner_summary` supplies `name` as the label.
      type: 'federation_partner',
      label: 'Federation Partner',
      permission: 'ai.federation.read',
      icon: 'Network',
      labelField: 'name',
      fetchById: (id: string) => communityAgentsApi.getFederationPartner(id).then((r) => r.partner),
    },
    {
      // getMissionTemplate resolves to ApiEnvelope<{ template }> — unwrap to the
      // template row. MissionTemplatesController gates index/show on `ai.missions.read`.
      type: 'mission_template',
      label: 'Mission Template',
      permission: 'ai.missions.read',
      icon: 'ClipboardList',
      labelField: 'name',
      fetchById: (id: string) => missionsApi.getMissionTemplate(id).then((r) => r.data.template),
    },
    {
      // getPage returns `{ data: Page }` — unwrap. Admin::PagesController gates
      // every action on `admin.access`.
      type: 'page',
      label: 'Page',
      permission: 'admin.access',
      icon: 'File',
      labelField: 'title',
      fetchById: (id: string) => pagesApi.getPage(id).then((r) => r.data),
    },
    {
      // A memory entry is addressed under its agent and keyed, so the id must be
      // composite "agentId:key". getMemory returns `{ memory }` — unwrap.
      // AgentMemoryController#show is gated by `ai.memory.read`.
      type: 'ai_persistent_context',
      label: 'Memory Entry',
      permission: 'ai.memory.read',
      icon: 'Brain',
      labelField: 'entry_key',
      fetchById: (id: string) => {
        const [agentId, key] = requireCompositeId(id, 2, 'agentId:key');
        return memoryApiService.getMemory(agentId, key).then((r) => r.memory);
      },
    },
    {
      // getAccount returns AccountResponse `{ success, data: Account }` — unwrap
      // to the account. AccountsController#show lets a user read their own
      // account; reading an arbitrary referenced account requires `accounts.read`
      // (enforced in `set_account`), so gate on that. The `show` serializer
      // emits `name`/`status`/`billing_email` — no secret material.
      type: 'account',
      label: 'Account',
      permission: 'accounts.read',
      icon: 'Building2',
      labelField: 'name',
      fetchById: (id: string) => accountsApi.getAccount(id).then((r) => r.data),
    },
    {
      // getRole returns `{ success, data: Role }` — unwrap to the role.
      // RolesController gates show on `admin.role.read`.
      type: 'role',
      label: 'Role',
      permission: 'admin.role.read',
      icon: 'Shield',
      labelField: 'name',
      fetchById: (id: string) => rolesApi.getRole(id).then((r) => r.data),
    },
    {
      // getPermission returns `{ success, data: Permission }` — unwrap to the
      // permission. PermissionsController#show requires an admin permission;
      // `admin.role.view` is the narrowest of the accepted set.
      type: 'permission',
      label: 'Permission',
      permission: 'admin.role.read',
      icon: 'Key',
      labelField: 'name',
      fetchById: (id: string) => rolesApi.getPermission(id).then((r) => r.data),
    },
    {
      // getCategory returns the raw axios response whose body is
      // `{ data: { category, articles } }` — unwrap to the category.
      // Kb::CategoriesController#show is public (auth optional), no permission.
      type: 'kb_category',
      label: 'KB Category',
      icon: 'FolderTree',
      labelField: 'name',
      fetchById: (id: string) => knowledgeBaseApi.getCategory(id).then((r) => r.data.data.category),
    },
    {
      // getTrace returns TraceData (already unwrapped from `{ success, data }`
      // by BaseApiService). ExecutionTracesController#show gates on
      // `ai_monitoring.read`. `name` is the trace's friendly label.
      type: 'execution_trace',
      label: 'Execution Trace',
      permission: 'ai_monitoring.read',
      icon: 'Activity',
      labelField: 'name',
      fetchById: (id: string) => executionTracesApi.getTrace(id),
    },
    {
      // getSession returns `{ session: ChatSession }` (already unwrapped) —
      // unwrap to the session. Chat::SessionsController#show is authenticated
      // and account-scoped (no resource permission). No `name` field; the
      // platform username is the friendliest label.
      type: 'chat_session',
      label: 'Chat Session',
      icon: 'MessagesSquare',
      labelField: 'platform_username',
      fetchById: (id: string) => chatChannelsApi.getSession(id).then((r) => r.session),
    },
    {
      // getAguiSession resolves to AguiSession (unwrapped from
      // `{ data: { session } }`). AguiController#show_session gates on
      // `ai.agents.read` (validate_permissions). No `name`; `thread_id` labels.
      type: 'agui_session',
      label: 'AG-UI Session',
      permission: 'ai.agents.read',
      icon: 'Workflow',
      labelField: 'thread_id',
      fetchById: (id: string) => getAguiSession(id),
    },
    {
      // getApprovalChain resolves to ApprovalChain (unwrapped from
      // `{ success, data }`). The single-chain show is the standalone
      // Ai::ApprovalChainsController (GET /ai/approval_chains/:id), gated on
      // `ai.approval_chains.manage` — the governance scope's approval_chains
      // route is index/create only.
      type: 'approval_chain',
      label: 'Approval Chain',
      permission: 'ai.approval_chains.manage',
      icon: 'GitMerge',
      labelField: 'name',
      fetchById: (id: string) => governanceApi.getApprovalChain(id),
    },
    {
      // getApprovalRequest returns `{ approval_request }` (unwrapped from the
      // outer `data`). GovernanceController#show_approval_request is
      // authenticated and account-scoped (`current_account.ai_approval_requests`),
      // with no resource permission. No `name`; `description` labels (falls back
      // to the type label when null).
      type: 'approval_request',
      label: 'Approval Request',
      icon: 'CheckSquare',
      labelField: 'description',
      fetchById: (id: string) => governanceApi.getApprovalRequest(id).then((r) => r.approval_request),
    },
    {
      // getCluster returns `ApiResponse<{ cluster }>` — unwrap to the cluster.
      // Devops::Swarm::ClustersController#show is authenticated and
      // account-scoped (no resource permission). The `show` serializer
      // (`cluster_details`) reports `has_tls_credentials` but never emits the
      // encrypted TLS material itself.
      type: 'swarm_cluster',
      label: 'Swarm Cluster',
      icon: 'Boxes',
      labelField: 'name',
      fetchById: (id: string) => swarmApi.getCluster(id).then((r) => r.data?.cluster),
    },
    {
      // getHarnessGap returns `ApiEnvelope<{ harness_gap }>` — unwrap to the gap.
      // CodeFactoryController gates show_harness_gap on `ai.code_factory.read`.
      // No `name`; `description` (NOT NULL) labels.
      type: 'harness_gap',
      label: 'Harness Gap',
      permission: 'ai.code_factory.read',
      icon: 'ShieldAlert',
      labelField: 'description',
      fetchById: (id: string) => codeFactoryApi.getHarnessGap(id).then((r) => r.data.harness_gap),
    },
    {
      // getEvidence returns `ApiEnvelope<{ evidence }>` — unwrap to the manifest.
      // CodeFactoryController gates show_evidence on `ai.code_factory.read`.
      // No `name`; `manifest_type` (NOT NULL) labels.
      type: 'evidence_manifest',
      label: 'Evidence Manifest',
      permission: 'ai.code_factory.read',
      icon: 'FileCheck',
      labelField: 'manifest_type',
      fetchById: (id: string) => codeFactoryApi.getEvidence(id).then((r) => r.data.evidence),
    },
  ]);
}

/**
 * Map a polymorphic backend type to a registered core entity `type`.
 *
 * Backend references arrive in several shapes: a Rails class name with a
 * namespace ("Ai::Agent"), a flat class name ("AiAgent"), or an already-short
 * form ("agent"). This normalizes all three to the registry key so a record can
 * render its subject as an `<EntityLink>`.
 *
 * Returns `undefined` for types with no registered core entity (the caller then
 * renders plain text). Aliases (e.g. "AiAgent" → "agent") collapse onto the
 * canonical registry type.
 */
export function resolveCoreEntityType(t: string): string | undefined {
  if (!t) return undefined;

  // Normalize "Ai::Agent" / "AiAgent" / "agent" → "agent": take the last
  // namespace segment, snake_case it, then strip a leading `ai_` prefix that the
  // registry keys omit (the platform's namespaced-FK convention: `Ai::` → `ai_`).
  const lastSegment = t.split('::').pop() ?? t;
  const snake = lastSegment
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1_$2')
    .toLowerCase();
  const stripped = snake.startsWith('ai_') ? snake.slice(3) : snake;

  // Canonical backend form / alias → registry type. Keys cover both the
  // class-derived snake form and common short forms the registry differs from.
  const MAP: Record<string, string> = {
    // Agents
    agent: 'agent',
    // Teams — `Ai::AgentTeam` snakes to `agent_team`; `Ai::Team` strips to `team`.
    agent_team: 'agent_team',
    team: 'agent_team',
    // Missions
    mission: 'mission',
    mission_template: 'mission_template',
    // Providers
    provider: 'ai_provider',
    ai_provider: 'ai_provider',
    // Skills
    skill: 'skill',
    // Users / accounts
    user: 'user',
    // `Account` snakes straight to `account`.
    account: 'account',
    // Roles & permissions (top-level models → snake straight through).
    role: 'role',
    permission: 'permission',
    // Conversations / chat
    conversation: 'conversation',
    chat_channel: 'chat_channel',
    channel: 'chat_channel',
    // `Chat::Session` → last segment `Session` → `session`. AG-UI sessions are
    // `Ai::AguiSession` (→ `agui_session`), so `session` is unambiguously chat.
    session: 'chat_session',
    chat_session: 'chat_session',
    // `Ai::AguiSession` → `agui_session` (no `ai_` prefix to strip).
    agui_session: 'agui_session',
    // Knowledge / RAG
    knowledge_base: 'knowledge_base',
    // `KnowledgeBase::Category` → last segment `Category` → `category`.
    category: 'kb_category',
    kb_category: 'kb_category',
    knowledge_base_category: 'kb_category',
    // A document/node maps to the generic document modal. Composite-id fetchers
    // still require a "knowledgeBaseId:documentId" id at the call site.
    knowledge_node: 'knowledge_node',
    document: 'knowledge_node',
    rag_document: 'knowledge_node',
    shared_knowledge: 'shared_knowledge',
    // MCP
    mcp_server: 'mcp_server',
    server: 'mcp_server',
    mcp_tool: 'mcp_tool',
    tool: 'mcp_tool',
    // Data sources
    data_source: 'data_source',
    // Workflows
    ralph_loop: 'ralph_loop',
    workspace: 'workspace',
    // DevOps
    devops_pipeline: 'devops_pipeline',
    devops_template: 'devops_pipeline',
    devops_pipeline_run: 'devops_pipeline_run',
    devops_execution: 'devops_pipeline_run',
    // Containers
    docker_container: 'docker_container',
    container: 'docker_container',
    container_instance: 'docker_container',
    // A2A
    agent_card: 'agent_card',
    // Federation — `FederationPartner` is a top-level model (no `Ai::` prefix),
    // so it snakes straight to `federation_partner`. Alias the short `partner`.
    federation_partner: 'federation_partner',
    partner: 'federation_partner',
    // CMS
    page: 'page',
    // Memory
    persistent_context: 'ai_persistent_context',
    memory_entry: 'ai_persistent_context',
    // Monitoring — `Ai::ExecutionTrace` → `execution_trace` (no `ai_` strip).
    execution_trace: 'execution_trace',
    trace: 'execution_trace',
    // Governance — `Ai::ApprovalChain`/`Ai::ApprovalRequest` snake straight.
    approval_chain: 'approval_chain',
    approval_request: 'approval_request',
    // Swarm — `Devops::SwarmCluster` → `swarm_cluster`.
    swarm_cluster: 'swarm_cluster',
    // Code factory — `Ai::CodeFactory::HarnessGap`/`EvidenceManifest` →
    // `harness_gap`/`evidence_manifest` (last namespace segment only).
    harness_gap: 'harness_gap',
    evidence_manifest: 'evidence_manifest',
  };

  return MAP[stripped] ?? MAP[snake];
}
