import { MANUAL_OPERATIONS_BUCKET, policyBucket } from './policyBucket';
import { interventionPolicyConfigSource } from './api/interventionPolicyConfigSource';

// IMP-82b43009d57b. The table below mirrors
// `Ai::InterventionPolicies::GroupedView.agent_bucket_for`:
//
//   policy.scope == "agent" && policy.agent ? policy.agent.name : "Manual Operations"
//
// The rows marked EXECUTION-VERIFIED are the literal output of that serializer,
// captured by driving the serializer this rule moved from (the System
// extension's autonomy endpoint, since folded into core's grouped view with the
// same fields) in a request spec and dumping the emitted keys and values — not read off the TypeScript type, because the
// whole finding is that a field's presence cannot be assumed across
// independently deployed modules. The full emitted key list was:
//
//   ["action_category", "agent_bucket", "agent_id", "agent_name",
//    "approval_chain_id", "approval_chain_name", "conditions", "id",
//    "is_active", "policy", "preferred_channels", "priority", "scope"]
//
// and `git show d975e94a^` shows the same list minus `agent_bucket`.
//
// `as never` throughout: these are deliberately MALFORMED rows, which is the
// point — the type says what a current server sends, and this function exists
// for payloads that do not match it.
const row = (fields: Record<string, unknown>) => fields as never;

describe('policyBucket', () => {
  it('is what the hook is actually given', () => {
    // Otherwise the panel and the hook group rows by different rules, and the
    // panel renders a group the hook holds no verb for.
    expect(interventionPolicyConfigSource.bucketForRow).toBe(policyBucket);
  });

  describe('the server shipped the bucket', () => {
    it('takes it verbatim, without re-deriving', () => {
      // Deliberately contradictory: scope says agent, the bucket says manual.
      // The server is the authority on its own grouping key — a client that
      // "corrected" this would be a second source of truth for the field.
      expect(
        policyBucket(
          row({ agent_bucket: 'Manual Operations', scope: 'agent', agent_name: 'Fleet Autonomy', agent_id: 'u' })
        )
      ).toBe('Manual Operations');
      expect(policyBucket(row({ agent_bucket: 'GitOps Reconciler' }))).toBe('GitOps Reconciler');
    });
  });

  describe('the server predates the bucket (d975e94a^)', () => {
    // EXECUTION-VERIFIED: created as scope "agent" with a Fleet Autonomy agent,
    // emitted with agent_bucket "Fleet Autonomy".
    it('reconstructs an agent-scoped row from scope + agent_name', () => {
      expect(policyBucket(row({ scope: 'agent', agent_name: 'Fleet Autonomy', agent_id: 'fleet-uuid' })))
        .toBe('Fleet Autonomy');
    });

    // EXECUTION-VERIFIED: created as scope "global", emitted with agent_name nil
    // and agent_bucket "Manual Operations".
    it('files a non-agent scope as manual', () => {
      expect(policyBucket(row({ scope: 'global', agent_name: null, agent_id: null })))
        .toBe(MANUAL_OPERATIONS_BUCKET);
    });

    // EXECUTION-VERIFIED, and the reason `agent_name || MANUAL_OPERATIONS_BUCKET`
    // is wrong: created as `scope: "action_type", ai_agent_id: <Fleet Autonomy>`,
    // the live serializer emits agent_name "Fleet Autonomy" AND agent_bucket
    // "Manual Operations". Nothing in Ai::InterventionPolicy forbids the
    // combination — `belongs_to :agent, optional: true`, no validation tying it
    // to scope — so this is a row shape, not a curiosity.
    it('consults scope BEFORE agent_name', () => {
      expect(policyBucket(row({ scope: 'action_type', agent_name: 'Fleet Autonomy', agent_id: 'fleet-uuid' })))
        .toBe(MANUAL_OPERATIONS_BUCKET);
    });

    // `p.agent&.name` is nil for a dangling or absent agent, and the server's
    // own rule buckets that as manual. An explicit null is the server answering.
    it('treats an explicit null agent_name on an agent-scoped row as manual', () => {
      expect(policyBucket(row({ scope: 'agent', agent_name: null, agent_id: 'gone' })))
        .toBe(MANUAL_OPERATIONS_BUCKET);
    });
  });

  describe('unplaceable', () => {
    it('answers null rather than inventing a bucket', () => {
      // Nothing the rule reads.
      expect(policyBucket(row({}))).toBeNull();
      expect(policyBucket(row({ policy: 'auto_approve' }))).toBeNull();
      // Agent-scoped, but the payload never says WHICH agent. The bucket IS the
      // agent's name, so an agent_id present on the row cannot stand in for it —
      // this is the case where a plausible answer is the harm.
      expect(policyBucket(row({ scope: 'agent', agent_id: 'u' }))).toBeNull();
      expect(policyBucket(row({ scope: 'agent', agent_name: '', agent_id: 'u' }))).toBeNull();
      expect(policyBucket(row({ scope: '', agent_name: 'Fleet Autonomy' }))).toBeNull();
      expect(policyBucket(null as never)).toBeNull();
      expect(policyBucket(undefined as never)).toBeNull();
    });

    // NAMED but not ADDRESSABLE. `identityOf` in core's hook refuses to coerce
    // (scope "agent", agent_id nil), so a save would degrade to category + verb,
    // which the update endpoint stores as an ACCOUNT-WIDE scope-"global" row —
    // written from a control labelled with one agent's name.
    it('refuses a reconstructed agent bucket it cannot address', () => {
      expect(policyBucket(row({ scope: 'agent', agent_name: 'Fleet Autonomy' }))).toBeNull();
      expect(policyBucket(row({ scope: 'agent', agent_name: 'Fleet Autonomy', agent_id: null }))).toBeNull();
      expect(policyBucket(row({ scope: 'agent', agent_name: 'Fleet Autonomy', agent_id: '' }))).toBeNull();
    });
  });
});

describe('interventionPolicyConfigSource', () => {
  it('reads the grouped view and saves through the bulk endpoint, both core routes', () => {
    expect(interventionPolicyConfigSource.fetchEndpoint).toBe('/ai/intervention_policies/grouped');
    expect(interventionPolicyConfigSource.updateEndpoint).toBe('/ai/intervention_policies/bulk');
  });
});
