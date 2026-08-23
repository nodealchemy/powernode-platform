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
  /**
   * Which by_agent bucket a `by_domain` row belongs to, or `null` when this
   * payload does not determine one.
   *
   * OPTIONAL, and its ABSENCE is meaningful: a source that does not set it is a
   * renderer that predates this seam, and such a renderer groups its rows by
   * `agent_bucket || 'Manual Operations'`. So the hook's fallback keeps exactly
   * that legacy rule — it must agree with the renderer it is paired with.
   * Answering "unplaceable" for an old renderer drops rows it still draws
   * controls for, which then show a verb the server never sent and save a
   * BROADER scope-"global" row than the one being edited.
   *
   * MUST HAVE A STABLE IDENTITY across renders — a module-level function, not
   * an inline arrow rebuilt with the source. It is read through a ref rather
   * than depended on, so an unstable one will not loop, but a changed rule only
   * takes effect on the next fetch.
   *
   * The extension supplies this because the RULE IS THE EXTENSION'S
   * (IMP-82b43009d57b). `agent_bucket` is computed by that extension's own
   * serializer, and an extension deployed against a server older than the field
   * is the one place where the rule has to be reconstructed from the fields that
   * server does ship. Core cannot know those fields, and core must not grow a
   * new exported module for them: `HOST_APP_IDS` is the extension build's
   * externals list, so a new id there makes the extension bundle unloadable by
   * any core that predates it — an outage in the OPPOSITE skew direction from
   * the one being fixed, and a silent one (`extensionLoader` logs and continues,
   * so the whole extension simply vanishes from the UI).
   *
   * Passing the rule as DATA through this existing seam is version-tolerant in
   * both directions: an older core ignores the extra property, and a newer core
   * given no property falls back to reading the field.
   *
   * Return `null` rather than a default for any row you cannot place, INCLUDING
   * one you can bucket but could not address (see `AutonomyPolicyUpdate`): the
   * hook drops such rows entirely, so a renderer that sets this MUST also render
   * those rows non-editably — dropping them from the map while still drawing a
   * control for them is the failure mode described above. Note the
   * addressability half only arises on a RECONSTRUCTION path: a row carrying
   * `agent_bucket` came from a server that has always shipped `scope` too.
   */
  bucketForRow?: (row: AutonomyDomainPolicy) => string | null;
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
 *
 * `agent_bucket` is OPTIONAL, alone among these, and that is deliberate
 * (IMP-82b43009d57b). It is the newest field on the row — the extension began
 * shipping it at d975e94a, long after the rest — and core and the System
 * extension deploy as SEPARATE modules, so a frontend running against a server
 * that predates it is a normal operational state rather than a hypothetical.
 * Marking it required told every reader it would be there and cost nothing at
 * runtime, which is how a whole account's autonomy posture came to be
 * misreported as manual. Never read it directly: `AutonomyConfigSource.
 * bucketForRow` is the single reader, it belongs to the extension whose server
 * emits the field, and it is the only thing that knows what to do when the field
 * is absent.
 */
export interface AutonomyDomainPolicy {
  action_category: string;
  agent_bucket?: string;
  policy: AutonomyLevel;
  scope: string;
  agent_id: string | null;
  /** Present since the row's first version; the fallback bucket reads it. */
  agent_name?: string | null;
}

/**
 * Server-owned grouping of policy rows: { domainKey: rows[] }. A settings panel
 * should build its sections from THIS rather than from a list of action
 * categories written into the component — the categories are defined and seeded
 * server-side, so a literal copy drifts the moment one is added.
 */
export type AutonomyDomainsMap = Record<string, AutonomyDomainPolicy[]>;
