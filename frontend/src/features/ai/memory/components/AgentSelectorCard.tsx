import React from 'react';
import { Brain } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import type { AiAgent } from '@/shared/types/ai';

interface AgentSelectorCardProps {
  agents: AiAgent[];
  selectedAgentId: string;
  onAgentChange: (id: string) => void;
}

/** Shared agent-selector card used by the memory surfaces. */
export const AgentSelectorCard: React.FC<AgentSelectorCardProps> = ({
  agents,
  selectedAgentId,
  onAgentChange,
}) => (
  <Card>
    <CardContent className="p-4">
      <div className="flex items-center gap-3">
        <Brain className="h-5 w-5 text-theme-primary shrink-0" />
        <label className="text-sm font-medium text-theme-secondary shrink-0">Agent:</label>
        <select
          value={selectedAgentId}
          onChange={(e) => onAgentChange(e.target.value)}
          className="flex-1 text-sm rounded-lg bg-theme-surface border border-theme text-theme-primary py-2 px-3 focus:outline-none focus:ring-2 focus:ring-theme-primary"
        >
          {agents.length === 0 && <option value="">No agents available</option>}
          {agents.map((agent) => (
            <option key={agent.id} value={agent.id}>
              {agent.name} ({agent.status})
            </option>
          ))}
        </select>
      </div>
    </CardContent>
  </Card>
);
