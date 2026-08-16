/**
 * Shared autonomy types — used by every extension's autonomy settings UI
 * (System and future extensions). Lives in core because autonomy is a
 * platform-wide feature, not an extension-specific one.
 */

export type AutonomyLevel = 'block' | 'require_approval' | 'notify_and_proceed' | 'auto_approve';

/**
 * Configuration for the parameterized useAutonomyConfig hook so any extension
 * can wire up a Settings UI against its own API endpoints. Each extension
 * provides its own AutonomyConfigSource; the hook itself is generic.
 */
export interface AutonomyConfigSource {
  /**
   * GET endpoint returning policy rows. Two shapes are accepted: the System API's
   * `{ data: { policies: { by_agent, by_domain } } }`, whose rows carry the
   * `scope`/`agent_id` an edit needs to address the row it came from; and a bare
   * `{ policies: { [agentName]: { [action]: { policy } } } }`, which carries no
   * row identity and whose edits can only be sent as category + verb.
   */
  fetchEndpoint: string;
  /**
   * PATCH endpoint for bulk updates. Accepts an `{ updates: AutonomyPolicyUpdate[] }`
   * body — see that type for why each entry carries the edited row's identity.
   */
  updateEndpoint: string;
}

/**
 * One entry of the PATCH body, and the reason a settings UI has to keep more of
 * a row than its verb.
 *
 * A policy row is keyed server-side by (account, action_category, scope,
 * ai_agent_id), so an update naming only the category does not edit the row the
 * operator was looking at — it upserts a SEPARATE scope-"global" row with a nil
 * agent. `Ai::InterventionPolicy#specificity_key` is lexicographic with
 * `ai_agent_id.present?` ranked above `priority`, so that new row cannot outrank
 * the agent-scoped one the seeds created at any priority: the operator's change
 * is silently decorative (IMP-bef43160636f).
 *
 * `scope` and `agent_id` therefore ride back exactly as the GET shipped them.
 * `agent_id` is nullable and the null is MEANINGFUL — omitting the key lets the
 * server infer `scope` from its absence.
 */
export interface AutonomyPolicyUpdate {
  action_category: string;
  policy: AutonomyLevel;
  scope?: string;
  agent_id?: string | null;
}

/** Per-agent policy map: { agentName: { action: level } } — frontend working state */
export type AgentPoliciesMap = Record<string, Record<string, AutonomyLevel>>;

/**
 * One policy row as the server groups it by domain. The fields a settings UI
 * needs to render a row it was never told about: which action it governs, which
 * agent bucket owns it (the same key the by_agent view is grouped under), and
 * its current level — plus the `scope` + `agent_id` that identify WHICH row it
 * is, without which an edit cannot be written back to it (see
 * `AutonomyPolicyUpdate`).
 *
 * `scope` and `agent_id` are required rather than optional because the server
 * has always shipped both (`System::AutonomyActions#serialize_policy`) and a
 * row missing either cannot be written back to. Note this only documents the
 * by_domain contract: the hook still tolerates their absence at RUNTIME, since
 * the other payload shapes it accepts carry no identity at all, and mock
 * responses are plain literals that no compiler checks against this type.
 */
export interface AutonomyDomainPolicy {
  action_category: string;
  agent_bucket: string;
  policy: AutonomyLevel;
  scope: string;
  agent_id: string | null;
}

/**
 * Server-owned grouping of policy rows: { domainKey: rows[] }. A settings panel
 * should build its sections from THIS rather than from a list of action
 * categories written into the component — the categories are defined and seeded
 * server-side, so a literal copy drifts the moment one is added.
 */
export type AutonomyDomainsMap = Record<string, AutonomyDomainPolicy[]>;
