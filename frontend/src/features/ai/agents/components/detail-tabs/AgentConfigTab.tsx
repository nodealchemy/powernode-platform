import React, { useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import type { AiAgent } from '@/shared/types/ai';

interface AgentConfigTabProps {
  agent: AiAgent;
}

const AGENT_TYPE_LABELS: Record<string, string> = {
  assistant: 'Assistant',
  code_assistant: 'Code Assistant',
  data_analyst: 'Data Analyst',
  content_generator: 'Content Generator',
  image_generator: 'Image Generator',
  workflow_optimizer: 'Workflow Optimizer',
  workflow_operations: 'Workflow Operations',
};

function ConfigRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between py-2 border-b border-theme last:border-b-0">
      <span className="text-sm text-theme-secondary flex-shrink-0 w-36">{label}</span>
      <span className="text-sm text-theme-primary text-right">{value ?? '—'}</span>
    </div>
  );
}

export const AgentConfigTab: React.FC<AgentConfigTabProps> = ({ agent }) => {
  const [mcpExpanded, setMcpExpanded] = useState(false);

  const hasMcpConfig = agent.mcp_tool_manifest &&
    Object.keys(agent.mcp_tool_manifest).length > 0 &&
    agent.mcp_tool_manifest.name;

  return (
    <div className="space-y-6">
      {/* Basic Info */}
      <div>
        <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-3">
          Basic Information
        </h4>
        <div className="bg-theme-surface border border-theme rounded-lg px-4">
          <ConfigRow label="Name" value={agent.name} />
          <ConfigRow
            label="Description"
            value={agent.description || <span className="text-theme-tertiary italic">No description</span>}
          />
          <ConfigRow label="Type" value={AGENT_TYPE_LABELS[agent.agent_type] || agent.agent_type} />
          <ConfigRow label="Status" value={agent.status} />
        </div>
      </div>

      {/* Model Settings */}
      <div>
        <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-3">
          Model Settings
        </h4>
        <div className="bg-theme-surface border border-theme rounded-lg px-4">
          <ConfigRow label="Provider" value={agent.provider?.name || '—'} />
          <ConfigRow label="Model" value={agent.model || '—'} />
          <ConfigRow label="Temperature" value={agent.temperature ?? '—'} />
          <ConfigRow label="Max Tokens" value={agent.max_tokens ?? '—'} />
        </div>
      </div>

      {/* System Prompt */}
      {agent.system_prompt && (
        <div>
          <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-3">
            System Prompt
          </h4>
          <pre className="bg-theme-surface border border-theme rounded-lg p-4 text-sm text-theme-primary whitespace-pre-wrap break-words max-h-60 overflow-y-auto font-mono">
            {agent.system_prompt}
          </pre>
        </div>
      )}

      {/* MCP Config */}
      {hasMcpConfig && (
        <div>
          <button
            onClick={() => setMcpExpanded(!mcpExpanded)}
            className="flex items-center gap-1.5 text-xs font-semibold text-theme-secondary uppercase tracking-wider mb-3 hover:text-theme-primary transition-colors"
          >
            {mcpExpanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
            MCP Configuration
          </button>
          {mcpExpanded && (
            <pre className="bg-theme-surface border border-theme rounded-lg p-4 text-xs text-theme-primary whitespace-pre-wrap break-words max-h-60 overflow-y-auto font-mono">
              {JSON.stringify(agent.mcp_tool_manifest, null, 2)}
            </pre>
          )}
        </div>
      )}
    </div>
  );
};
