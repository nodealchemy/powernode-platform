import { useState, useEffect, useCallback } from 'react';
import apiClient from '@/shared/services/apiClient';
import type {
  AgentPoliciesMap,
  AutonomyConfigSource,
  AutonomyDomainPolicy,
  AutonomyDomainsMap,
  AutonomyLevel,
} from '@/shared/types/autonomy';
import { logger } from '@/shared/utils/logger';

/**
 * Parameterized hook for managing autonomy policy configuration in any
 * extension. Pass an `AutonomyConfigSource` describing how to fetch + update
 * policies and how to map agent names → role strings; the hook handles the
 * dirty-tracking + optimistic state management.
 *
 * Each extension constructs its own source — this hook is generic
 * enough that future extensions plug in identically.
 */
export function useAutonomyConfig(source: AutonomyConfigSource) {
  const [agentPolicies, setAgentPolicies] = useState<AgentPoliciesMap>({});
  const [domains, setDomains] = useState<AutonomyDomainsMap>({});
  const [localOverrides, setLocalOverrides] = useState<AgentPoliciesMap>({});
  const [loading, setLoading] = useState(true);

  const fetchPolicies = useCallback(() => {
    setLoading(true);
    apiClient
      .get(source.fetchEndpoint)
      .then((res) => {
        const raw = res.data?.data?.policies?.by_agent || res.data?.policies || {};
        const byAgent: AgentPoliciesMap = {};

        Object.entries(raw).forEach(([agentName, actions]) => {
          byAgent[agentName] = {};
          if (Array.isArray(actions)) {
            // System API shape: array of policy objects per agent
            (actions as Array<{ action_category: string; policy: AutonomyLevel }>).forEach((p) => {
              byAgent[agentName][p.action_category] = p.policy ?? 'require_approval';
            });
          } else if (actions && typeof actions === 'object') {
            // Nested-object API shape: { action_category: { policy: ... } }
            Object.entries(actions as Record<string, { policy: AutonomyLevel }>).forEach(
              ([action, info]) => {
                byAgent[agentName][action] = info?.policy ?? 'require_approval';
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
              const bucket = row.agent_bucket;
              if (!bucket) return;
              byAgent[bucket] = byAgent[bucket] || {};
              if (byAgent[bucket][row.action_category] === undefined) {
                byAgent[bucket][row.action_category] = row.policy ?? 'require_approval';
              }
            });
          });
        }

        setAgentPolicies(byAgent);
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

  const save = useCallback(async () => {
    const agentNames = Object.keys(localOverrides);
    if (agentNames.length === 0) return;

    await Promise.all(
      agentNames
        .filter((name) => Object.keys(localOverrides[name] || {}).length > 0)
        .map((name) =>
          apiClient.patch(source.updateEndpoint, {
            policies: localOverrides[name],
            agent_role: source.roleForAgent(name),
          })
        )
    );

    setAgentPolicies((prev) => {
      const merged = { ...prev };
      for (const [name, actions] of Object.entries(localOverrides)) {
        merged[name] = { ...merged[name], ...actions };
      }
      return merged;
    });
    setLocalOverrides({});
  }, [localOverrides, source]);

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
