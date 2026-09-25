import type { AutonomyDomainPolicy } from '@/shared/types/autonomy';

/** The server's catch-all bucket for every row that is not agent-scoped. */
export const MANUAL_OPERATIONS_BUCKET = 'Manual Operations';

/**
 * Which agent group one of the grouped view's `by_domain` rows belongs to, or
 * `null` when the payload does not determine one.
 *
 * SINGLE AUTHORITY for that question on the client. The policy panel groups
 * rows with it and `useAutonomyConfig` reads verbs and row identities with it
 * (via `interventionPolicyConfigSource.bucketForRow`), so the two cannot
 * disagree about which group a row is in — a disagreement renders a control the
 * hook holds no verb for, which reads as a confident `require_approval` and
 * then refuses every edit.
 *
 * The server's rule (`Ai::InterventionPolicies::GroupedView.agent_bucket_for`)
 * is
 *
 *   policy.scope == "agent" && policy.agent ? policy.agent.name : "Manual Operations"
 *
 * WHY A FALLBACK IS NEEDED AT ALL (IMP-82b43009d57b). The frontend and the
 * server deploy separately, so a frontend newer than the server is a normal
 * operational state, and a row can arrive without `agent_bucket`. This rule
 * came from the System extension's panel, where exactly that happened: reading
 * a missing bucket as "Manual Operations" collapsed every agent-scoped row into
 * the manual group. The panel showed a uniform, wrong picture of the account's
 * posture, and the manual group's bulk "Set all" could then write verbs onto
 * agent policies the operator never chose to touch.
 *
 * WHY NOT `row.agent_name || MANUAL_OPERATIONS_BUCKET`. Because it is
 * confidently wrong for a real row shape. `Ai::InterventionPolicy::SCOPES` is
 * global / agent / action_type and NOTHING ties `ai_agent_id` to the scope
 * (`belongs_to :agent, optional: true`, no validation). Verified by execution
 * against the live serializer: a row created as `scope: "action_type",
 * ai_agent_id: <Fleet Autonomy>` is emitted with `agent_name: "Fleet Autonomy"`
 * AND `agent_bucket: "Manual Operations"`. Keying on the name alone files it
 * under an agent the server never put it in. `scope` is consulted first.
 */
export function policyBucket(row: AutonomyDomainPolicy): string | null {
  if (!row || typeof row !== 'object') return null;

  // The server told us. Authoritative — this is the value `by_agent_pivot`
  // grouped with, including for the buckets that view drops, so a later change
  // to the server's rule needs no change here.
  if (typeof row.agent_bucket === 'string' && row.agent_bucket !== '') return row.agent_bucket;

  // Old-shape payload. Reconstruct `agent_bucket_for` from the fields it reads.
  // No scope is undeterminable, and it is also unaddressable — `identityOf` in
  // the shared hook refuses a row without one — so `null` is right on both counts.
  if (typeof row.scope !== 'string' || row.scope === '') return null;
  if (row.scope !== 'agent') return MANUAL_OPERATIONS_BUCKET;

  // scope == "agent", so the bucket is the agent's NAME. `agent_id` cannot
  // stand in for it: knowing a row is agent-scoped without knowing WHICH agent
  // is precisely the undeterminable case.
  if (typeof row.agent_name !== 'string' || row.agent_name === '') {
    // An explicit null is the server ANSWERING — `p.agent&.name` is nil for a
    // dangling or absent agent, which its own rule buckets as manual. A missing
    // key is a server that never told us.
    return 'agent_name' in row && row.agent_name === null ? MANUAL_OPERATIONS_BUCKET : null;
  }

  // Named, but is it ADDRESSABLE? `identityOf` in the shared hook refuses to coerce
  // `(scope: "agent", agent_id: nil)`, so a save for this row would degrade to
  // category + verb — which the update endpoint stores as a scope-"global" row.
  // That is an ACCOUNT-WIDE policy written from a control labelled with one
  // agent's name, so answering `null` and rendering it read-only is the honest
  // outcome. The check lives HERE, in the same function the panel groups with,
  // rather than as a second predicate in the hook: split across two files, the
  // panel renders a group the hook holds no verb for.
  if (typeof row.agent_id !== 'string' || row.agent_id === '') return null;

  return row.agent_name;
}
