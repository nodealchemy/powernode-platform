import React from 'react';
import { Terminal, Sparkles } from 'lucide-react';

interface AgentBadgeProps {
  agentType?: string;
}

/** Color-code sender names by agent type for quick visual differentiation. */
export function getAgentNameColorClass(agentType?: string): string {
  if (!agentType) return 'text-theme-primary'; // User — default theme text
  if (agentType === 'mcp_client') return 'text-theme-info'; // MCP — blue (matches MCP badge)
  if (agentType === 'assistant') return 'text-theme-interactive-primary'; // AI — purple (matches AI badge)
  return 'text-theme-primary'; // Fallback
}

/**
 * Renders a small badge indicating the agent type (MCP or AI).
 * Shared between ChatMessage (floating chat) and MessageList (full conversation).
 *
 * - mcp_client → "MCP" badge with Terminal icon (info theme)
 * - assistant  → "AI" badge with Sparkles icon (purple/interactive theme)
 * - other/undefined → no badge rendered
 */
export const AgentBadge: React.FC<AgentBadgeProps> = ({ agentType }) => {
  if (agentType === 'mcp_client') {
    return (
      <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-medium bg-theme-info/10 text-theme-info rounded-full">
        <Terminal className="h-2.5 w-2.5" aria-hidden="true" />
        MCP
      </span>
    );
  }

  if (agentType === 'assistant') {
    return (
      <span className="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-medium bg-theme-interactive-primary/10 text-theme-interactive-primary rounded-full">
        <Sparkles className="h-2.5 w-2.5" aria-hidden="true" />
        AI
      </span>
    );
  }

  return null;
};
