import { useState, useEffect, useCallback } from 'react';
import apiClient from '@/shared/services/apiClient';
import type {
  AgentPoliciesMap,
  AutonomyConfigSource,
  AutonomyDomainPolicy,
  AutonomyDomainsMap,
  AutonomyLevel,
  AutonomyPolicyUpdate,
} from '@/shared/types/autonomy';
import { logger } from '@/shared/utils/logger';

/**
 * Parameterized hook for managing autonomy policy configuration in any
 * extension. Pass an `AutonomyConfigSource` naming the endpoints to fetch from
 * and update; the hook handles the dirty-tracking + optimistic state
 * management, and remembers which server row each control was rendered from so
 * `save()` can write back to that row.
 *
 * Each extension constructs its own source — this hook is generic
 * enough that future extensions plug in identically.
 */
/**
 * Which server row a control's displayed verb came from — the (scope, agent_id)
 * half of that row's key. `save()` writes back to exactly this row.
 */
type RowIdentity = { scope: string; agent_id: string | null };

/** Per-bucket, per-category row identities. Same keying as AgentPoliciesMap. */
type RowIdentityMap = Record<string, Record<string, RowIdentity>>;

/**
 * A serialized row's identity, or undefined for a payload shape that omits it —
 * in which case save() falls back to sending the category alone.
 *
 * A scope-"agent" row with no agent id is refused rather than coerced. That
 * pair would upsert `(scope: "agent", ai_agent_id: nil)`, which
 * Ai::InterventionPolicyService#resolve calls out by name as the malformed row
 * its audience allowlist exists to keep from binding every agent in the
 * account. Degrading to category-only is a decorative write; minting that key
 * is a harmful one.
 */
function identityOf(row: { scope?: unknown; agent_id?: unknown }): RowIdentity | undefined {
  if (typeof row?.scope !== 'string') return undefined;

  const agentId = typeof row.agent_id === 'string' ? row.agent_id : null;
  if (row.scope === 'agent' && agentId === null) return undefined;

  return { scope: row.scope, agent_id: agentId };
}

export function useAutonomyConfig(source: AutonomyConfigSource) {
  const [agentPolicies, setAgentPolicies] = useState<AgentPoliciesMap>({});
  const [domains, setDomains] = useState<AutonomyDomainsMap>({});
  const [localOverrides, setLocalOverrides] = useState<AgentPoliciesMap>({});
  const [rowIdentities, setRowIdentities] = useState<RowIdentityMap>({});
  const [loading, setLoading] = useState(true);

  const fetchPolicies = useCallback(() => {
    setLoading(true);
    apiClient
      .get(source.fetchEndpoint)
      .then((res) => {
        const raw = res.data?.data?.policies?.by_agent || res.data?.policies || {};
        const byAgent: AgentPoliciesMap = {};
        const identities: RowIdentityMap = {};

        // The displayed verb and the identity save() writes back are set
        // TOGETHER, by every branch below, so the two can never name different
        // rows. Where a payload shape carries no identity (the nested-object
        // extension shape) the identity is cleared rather than left behind from
        // an earlier row — a stale one would send the edit to the wrong row,
        // which is the whole defect this replaced.
        const setPolicy = (
          bucket: string,
          category: string,
          level: AutonomyLevel,
          identity?: RowIdentity
        ) => {
          byAgent[bucket] = byAgent[bucket] || {};
          byAgent[bucket][category] = level;

          identities[bucket] = identities[bucket] || {};
          if (identity) identities[bucket][category] = identity;
          else delete identities[bucket][category];
        };

        Object.entries(raw).forEach(([agentName, actions]) => {
          byAgent[agentName] = {};
          if (Array.isArray(actions)) {
            // System API shape: array of policy objects per agent
            (
              actions as Array<{
                action_category: string;
                policy: AutonomyLevel;
                scope?: string;
                agent_id?: string | null;
              }>
            ).forEach((p) => {
              setPolicy(agentName, p.action_category, p.policy ?? 'require_approval', identityOf(p));
            });
          } else if (actions && typeof actions === 'object') {
            // Nested-object API shape: { action_category: { policy: ... } }
            Object.entries(actions as Record<string, { policy: AutonomyLevel }>).forEach(
              ([action, info]) => {
                setPolicy(agentName, action, info?.policy ?? 'require_approval');
              }
            );
          }
        });

        // Domain view: the server's own grouping of the SAME rows. It is the
        // complete set — the by_agent view above buckets a row under its owning
        // agent and then keeps only the buckets the endpoint declares, so a row
        // owned by any other agent is absent there but present here. Back-fill
        // rather than overwrite: where both carry a category the value is
        // identical (one row, two pivots), and back-filling keeps an API that
        // ships by_agent alone behaving exactly as before.
        const byDomain = res.data?.data?.policies?.by_domain;
        const domainMap: AutonomyDomainsMap = {};

        if (byDomain && typeof byDomain === 'object') {
          Object.entries(byDomain as Record<string, unknown>).forEach(([domain, rows]) => {
            if (!Array.isArray(rows)) return;
            const parsed = (rows as AutonomyDomainPolicy[]).filter((r) => r?.action_category);
            domainMap[domain] = parsed;

            parsed.forEach((row) => {
              // Same default SystemSettingsPanel's buildGroups applies. The two
              // used to disagree — this one skipped a blank bucket while the
              // panel rendered it under 'Manual Operations' — which left that
              // control with no verb AND no identity, so an edit to it would
              // land the identity-less write this change exists to stop.
              // Unreachable while agent_bucket_for always returns a name, but
              // two files must not encode different rules for one field.
              const bucket = row.agent_bucket || 'Manual Operations';
              byAgent[bucket] = byAgent[bucket] || {};
              if (byAgent[bucket][row.action_category] === undefined) {
                setPolicy(bucket, row.action_category, row.policy ?? 'require_approval', identityOf(row));
              }
            });
          });
        }

        setAgentPolicies(byAgent);
        setRowIdentities(identities);
        setDomains(domainMap);
        setLocalOverrides({});
      })
      .catch((err) => logger.error('Failed to load autonomy policies', err))
      .finally(() => setLoading(false));
  }, [source.fetchEndpoint]);

  useEffect(() => {
    fetchPolicies();
  }, [fetchPolicies]);

  const getPolicy = useCallback(
    (agentName: string, action: string): AutonomyLevel => {
      return (
        localOverrides[agentName]?.[action] ??
        agentPolicies[agentName]?.[action] ??
        'require_approval'
      );
    },
    [agentPolicies, localOverrides]
  );

  const updatePolicy = useCallback(
    (agentName: string, action: string, level: AutonomyLevel) => {
      setLocalOverrides((prev) => ({
        ...prev,
        [agentName]: { ...prev[agentName], [action]: level },
      }));
    },
    []
  );

  /**
   * Persist every pending edit in ONE request.
   *
   * Each entry carries the identity of the row its control was rendered from,
   * so the upsert lands on that row instead of creating a parallel
   * scope-"global" one the seeded agent-scoped row would outrank forever
   * (IMP-bef43160636f). A bucket whose rows arrived without an identity — the
   * nested-object payload shape — sends category + verb alone, which is all the
   * server can key on for those.
   *
   * One request rather than one per bucket, because the endpoint takes a bulk
   * array across agents and reports `{errors, changed}` for the whole batch.
   * Note this does NOT make the save atomic — #update persists row by row, so a
   * rejected entry still leaves earlier ones written. It removes the second,
   * dumber partial-failure mode where some buckets' requests succeeded and
   * later ones never went out.
   */
  const save = useCallback(async () => {
    const updates: AutonomyPolicyUpdate[] = Object.entries(localOverrides).flatMap(
      ([bucket, actions]) =>
        Object.entries(actions || {}).map(([action_category, policy]) => {
          const identity = rowIdentities[bucket]?.[action_category];
          return identity
            ? { action_category, policy, scope: identity.scope, agent_id: identity.agent_id }
            : { action_category, policy };
        })
    );

    if (updates.length === 0) return;

    await apiClient.patch(source.updateEndpoint, { updates });

    setAgentPolicies((prev) => {
      const merged = { ...prev };
      for (const [name, actions] of Object.entries(localOverrides)) {
        merged[name] = { ...merged[name], ...actions };
      }
      return merged;
    });
    setLocalOverrides({});
  }, [localOverrides, rowIdentities, source]);

  return {
    agentPolicies,
    agentNames: Object.keys(agentPolicies),
    domains,
    loading,
    getPolicy,
    updatePolicy,
    save,
    reload: fetchPolicies,
    isDirty: Object.keys(localOverrides).length > 0,
  };
}
