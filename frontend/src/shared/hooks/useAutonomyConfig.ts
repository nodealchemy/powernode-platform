import { useState, useEffect, useCallback } from 'react';
import apiClient from '@/shared/services/apiClient';
import type {
  AgentPoliciesMap,
  AutonomyConfigSource,
  AutonomyLevel,
} from '@/shared/types/autonomy';
import { logger } from '@/shared/utils/logger';

/**
 * Parameterized hook for managing autonomy policy configuration in any
 * extension. Pass an `AutonomyConfigSource` describing how to fetch + update
 * policies and how to map agent names → role strings; the hook handles the
 * dirty-tracking + optimistic state management.
 *
 * Trading and System each construct their own source — this hook is generic
 * enough that future extensions plug in identically.
 */
export function useAutonomyConfig(source: AutonomyConfigSource) {
  const [agentPolicies, setAgentPolicies] = useState<AgentPoliciesMap>({});
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
            // Trading API shape: { action_category: { policy: ... } }
            Object.entries(actions as Record<string, { policy: AutonomyLevel }>).forEach(
              ([action, info]) => {
                byAgent[agentName][action] = info?.policy ?? 'require_approval';
              }
            );
          }
        });

        setAgentPolicies(byAgent);
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
    loading,
    getPolicy,
    updatePolicy,
    save,
    reload: fetchPolicies,
    isDirty: Object.keys(localOverrides).length > 0,
  };
}
