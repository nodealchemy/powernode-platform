import React, { useState } from 'react';
import { GitBranch } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { useAgentLineage, useAgentLineageForest } from '@/features/ai/autonomy/api/autonomyApi';
import { AgentLineageTree } from '@/features/ai/autonomy/components/AgentLineageTree';
import { DelegationPolicyPanel } from '@/features/ai/autonomy/components/DelegationPolicyPanel';
import type { AgentLineageNode } from '@/features/ai/autonomy/types/autonomy';

/** Every node the forest can render, flattened and sorted by name — the picker lists exactly these. */
function flattenLineageNodes(nodes: AgentLineageNode[], acc: AgentLineageNode[] = []): AgentLineageNode[] {
  for (const node of nodes) {
    acc.push(node);
    flattenLineageNodes(node.children ?? [], acc);
  }
  return acc;
}

/** Control → Trust & Lineage → Lineage: the spawn/clone forest, one agent's tree, and delegation policies. */
export const LineageTab: React.FC = () => {
  const [selectedAgentId, onAgentSelect] = useState('');
  const { data: forest, isLoading: forestLoading } = useAgentLineageForest();
  const { data: singleLineage } = useAgentLineage(selectedAgentId);
  const [showOrphans, setShowOrphans] = useState(false);
  const pickerAgents = forest
    ? flattenLineageNodes([...forest.trees, ...forest.orphans]).sort((a, b) => a.name.localeCompare(b.name))
    : [];

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader title="Agent Lineage" />
        <CardContent>
          <div className="mb-4">
            <label className="block text-sm text-theme-tertiary mb-1">Filter by Agent (optional)</label>
            <select
              className="w-full max-w-xs rounded-md border border-theme bg-theme-surface text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info-fg"
              value={selectedAgentId}
              onChange={(e) => onAgentSelect(e.target.value)}
            >
              <option value="">All agents (forest view)</option>
              {pickerAgents.map((agent) => (
                <option key={agent.id} value={agent.id}>
                  {agent.name}{agent.canonical ? ' (canonical)' : ''}
                </option>
              ))}
            </select>
          </div>

          {selectedAgentId ? (
            singleLineage ? (
              <AgentLineageTree root={singleLineage} />
            ) : (
              <p className="text-sm text-theme-tertiary py-4 text-center">Loading lineage...</p>
            )
          ) : forestLoading ? (
            <p className="text-sm text-theme-tertiary py-4 text-center">Loading lineage forest...</p>
          ) : forest && forest.trees.length > 0 ? (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {forest.trees.map((tree) => (
                <div key={tree.id} className="border border-theme rounded-lg p-3">
                  <AgentLineageTree root={tree} />
                </div>
              ))}
            </div>
          ) : (
            <p className="text-sm text-theme-tertiary py-4 text-center">
              No lineage trees found. A lineage row is written when an agent is spawned or cloned from a parent;
              team membership alone does not create one.
            </p>
          )}

          {!selectedAgentId && forest && forest.orphans.length > 0 && (
            <div className="mt-4">
              <button
                onClick={() => setShowOrphans(!showOrphans)}
                className="text-sm text-theme-info-fg hover:underline flex items-center gap-1"
              >
                <GitBranch className="h-3.5 w-3.5" />
                {showOrphans ? 'Hide' : 'Show'} Root agents (no parent) ({forest.orphans.length})
              </button>
              {showOrphans && (
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-3 mt-3">
                  {forest.orphans.map((agent) => (
                    <div key={agent.id} className="border border-theme rounded-lg p-3">
                      <AgentLineageTree root={agent} />
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>
      <DelegationPolicyPanel />
    </div>
  );
};
