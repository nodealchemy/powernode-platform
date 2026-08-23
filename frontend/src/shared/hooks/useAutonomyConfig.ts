import { useState, useEffect, useCallback, useRef } from 'react';
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

/**
 * Which by_agent bucket a by_domain row belongs to, when the source named no
 * rule of its own.
 *
 * This KEEPS the legacy `|| 'Manual Operations'` default on purpose, and the
 * reason is a packaging fact rather than a preference (IMP-82b43009d57b).
 *
 * A source with no `bucketForRow` is, by construction, a renderer that predates
 * the seam — and that renderer groups its rows by
 * `row.agent_bucket || 'Manual Operations'`. Core's job here is to AGREE WITH
 * ITS RENDERER. Answering "unplaceable" instead drops the row from
 * `agentPolicies` and `rowIdentities` while that panel still renders a control
 * for it, so the control shows the miss default `require_approval` — a verb the
 * server never sent — and its save degrades to category + verb, which
 * `System::AutonomyActions#update` resolves as `scope: "global"`. That is a
 * BROADER, account-wide write than the agent row the operator was editing:
 * strictly worse than the mislabel it would be replacing.
 *
 * Concretely, `powernode-extension-system` ships the panel, the source AND the
 * Rails serializer in ONE module (its manifest file_spec covers both
 * `/opt/powernode/extensions/system/**` and
 * `/opt/powernode/frontend/dist/extensions/system/**`), so an old source
 * implies an old panel. Core cannot fix that pairing's mislabel from here — the
 * old panel's grouping is baked into the old bundle — and it must not make the
 * pairing worse.
 *
 * The honest degradation this IMP is about is therefore delivered through
 * `bucketForRow`, where a renderer that ASKED for it can act on it: it can
 * answer `null` and render those rows read-only. That path is exercised when
 * the panel ships with CORE instead — core's monolithic build glob-imports
 * every `extensions/*​/frontend/src/register.ts` eagerly
 * (`extensionLoader.ts`), so there the panel is new while the extension
 * module's serializer can still be old.
 */
function defaultBucketForRow(row: { agent_bucket?: unknown }): string | null {
  return typeof row.agent_bucket === 'string' && row.agent_bucket !== ''
    ? row.agent_bucket
    : 'Manual Operations';
}

export function useAutonomyConfig(source: AutonomyConfigSource) {
  const [agentPolicies, setAgentPolicies] = useState<AgentPoliciesMap>({});
  const [domains, setDomains] = useState<AutonomyDomainsMap>({});
  const [localOverrides, setLocalOverrides] = useState<AgentPoliciesMap>({});
  const [rowIdentities, setRowIdentities] = useState<RowIdentityMap>({});
  const [loading, setLoading] = useState(true);

  // See the dependency list of `fetchPolicies` for why this is a ref.
  const bucketForRowRef = useRef(source.bucketForRow);
  bucketForRowRef.current = source.bucketForRow;

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
              // ONE rule for this field, and it is the SOURCE's — the panel that
              // renders these rows into groups must call the same function, or
              // the two encode different rules for one field and a group appears
              // that this map has no verb for.
              const rule = bucketForRowRef.current;
              const bucket = rule ? rule(row) : defaultBucketForRow(row);

              // Unplaceable: we cannot say whose posture this row is, so any
              // group we filed it under would be invented — and an invented
              // group is what carries an edit to the wrong row. Attribute it to
              // nothing and let the renderer say so.
              //
              // ADDRESSABILITY is the source's business, not a second predicate
              // here. A source that can name a bucket only by reconstructing it
              // must also confirm the row can be written back to, and answer
              // `null` when it cannot (see `AutonomyConfigSource.bucketForRow`).
              // Splitting the two predicates across the two files is what makes
              // a panel render a group this map holds no verb for.
              if (bucket === null) return;

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
    // `bucketForRow` is deliberately NOT a dependency, and is read through a ref
    // rather than captured. It is a FUNCTION on a caller-owned object, so a
    // source built inline — "each extension constructs its own source", the
    // documented usage — hands us a new identity on every render. As a dep that
    // makes `fetchPolicies` change identity, which refires the effect below,
    // which re-renders: measured at 19 GETs from one mount plus three
    // re-renders. The endpoint string is the only thing that should ever cause
    // a refetch; a changed rule takes effect on the next one.
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

  /**
   * The ONLY door into `localOverrides`, and therefore the only door onto the
   * wire — `save()` sends exactly what this let in. So the refusal below is the
   * whole of "an unreadable row cannot become a write"; a second filter in
   * `save()` would guard a state that cannot exist and could never be tested
   * apart from this one.
   *
   * A bucket absent from `agentPolicies` is refused. That set is every bucket
   * the payload produced — the by_agent pivot's own keys plus every bucket a
   * by_domain row was placeable into — so naming anything else means the caller
   * is editing a group this hook has no row for. Rows it could not place are
   * exactly the ones missing from it (IMP-82b43009d57b).
   *
   * Keyed on membership rather than on a sentinel bucket NAME on purpose: a
   * bucket name is an `Ai::Agent#name`, `Ai::Agent` validates no format, and a
   * magic string would therefore be a name a real agent can hold — making that
   * agent's policies silently unconfigurable the day someone picks it.
   */
  const updatePolicy = useCallback(
    (agentName: string, action: string, level: AutonomyLevel) => {
      if (agentPolicies[agentName] === undefined) {
        logger.warn('Refusing an autonomy edit for a bucket no policy row was read into', {
          bucket: agentName,
          action,
        });
        return;
      }

      setLocalOverrides((prev) => ({
        ...prev,
        [agentName]: { ...prev[agentName], [action]: level },
      }));
    },
    [agentPolicies]
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
