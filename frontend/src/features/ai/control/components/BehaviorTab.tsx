import React, { useState } from 'react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { useTrustScores } from '@/features/ai/autonomy/api/autonomyApi';
import { BehavioralFingerprintChart } from '@/features/ai/autonomy/components/BehavioralFingerprintChart';

/**
 * Control → Trust & Lineage → Behavior: one agent's behavioural fingerprint.
 * The chart used to sit under Autonomy → Security and only drew once an agent
 * had been picked on the Lineage section; it gets its own picker here, over
 * the agents that have a trust score (the ones being evaluated).
 */
export const BehaviorTab: React.FC = () => {
  const { data: trustScores } = useTrustScores();
  const [agentId, setAgentId] = useState('');
  const agents = [...(trustScores ?? [])].sort((a, b) => (a.agent_name ?? '').localeCompare(b.agent_name ?? ''));

  return (
    <Card>
      <CardHeader title="Behavioral fingerprint" />
      <CardContent className="space-y-4">
        <label className="block text-sm text-theme-tertiary">
          Agent
          <select
            aria-label="Agent"
            className="block mt-1 w-full max-w-xs rounded-md border border-theme bg-theme-surface text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info-fg"
            value={agentId}
            onChange={(e) => setAgentId(e.target.value)}
          >
            <option value="">Select an agent…</option>
            {agents.map((score) => (
              <option key={score.agent_id} value={score.agent_id}>{score.agent_name || score.agent_id}</option>
            ))}
          </select>
        </label>
        {agentId ? (
          <BehavioralFingerprintChart agentId={agentId} />
        ) : (
          <p className="text-sm text-theme-tertiary">Choose an agent to see its behavioural fingerprint.</p>
        )}
      </CardContent>
    </Card>
  );
};
