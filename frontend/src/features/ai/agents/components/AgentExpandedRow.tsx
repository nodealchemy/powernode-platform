import React from 'react';
import {
  Cpu, Clock, Wrench, Settings, FileText, Hash, User,
} from 'lucide-react';
import {
  AGENT_TYPE_LABELS, timeAgo, successRateColor, formatDuration,
} from '../constants/agentConstants';
import { EntityLink } from '@/shared/components/entity';
import { cn } from '@/shared/utils/cn';
import type { AiAgent } from '@/shared/types/ai';

interface AgentExpandedRowProps {
  agent: AiAgent;
}

export const AgentExpandedRow: React.FC<AgentExpandedRowProps> = ({ agent }) => {
  const execStats = agent.execution_stats;
  const hasExecutions = Boolean(execStats?.total_executions);
  const trustLevel = (agent as AiAgent & { trust_level?: string }).trust_level;
  const version = (agent as AiAgent & { mcp_tool_manifest?: { version?: string } }).mcp_tool_manifest?.version;
  const createdBy = (agent as AiAgent & { created_by?: { name?: string } }).created_by;

  return (
    <tr>
      <td colSpan={7} className="p-0">
        <div className="border-l-2 border-theme-info mx-4 my-3 ml-6 pl-5 pr-2">
          {/* Description */}
          {agent.description && (
            <p className="text-sm text-theme-secondary mb-4 max-w-3xl">
              {agent.description}
            </p>
          )}

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            {/* Column 1: Configuration */}
            <div className="space-y-3">
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Configuration</h4>
              <div className="space-y-2">
                <DetailRow
                  icon={Cpu}
                  label="Provider"
                  value={
                    agent.provider?.id ? (
                      <span className="inline-flex items-center gap-1">
                        <EntityLink type="ai_provider" id={agent.provider.id} label={agent.provider.name} className="font-medium truncate" />
                        {agent.model ? <span className="text-theme-primary">/ {agent.model}</span> : null}
                      </span>
                    ) : (
                      `${agent.provider?.name || 'None'}${agent.model ? ` / ${agent.model}` : ''}`
                    )
                  }
                />
                <DetailRow icon={Settings} label="Type" value={AGENT_TYPE_LABELS[agent.agent_type] || agent.agent_type} />
                {agent.temperature != null && (
                  <DetailRow icon={Hash} label="Temperature" value={String(agent.temperature)} />
                )}
                {agent.max_tokens != null && (
                  <DetailRow icon={Hash} label="Max Tokens" value={agent.max_tokens.toLocaleString()} />
                )}
                {version && (
                  <DetailRow icon={Hash} label="Version" value={`v${version}`} />
                )}
                {trustLevel && (
                  <DetailRow icon={Settings} label="Trust" value={trustLevel.charAt(0).toUpperCase() + trustLevel.slice(1)} />
                )}
                {agent.skills && agent.skills.length > 0 && (
                  <div className="flex items-start gap-2 text-xs">
                    <Wrench className="h-3.5 w-3.5 text-theme-tertiary flex-shrink-0 mt-0.5" />
                    <span className="text-theme-secondary shrink-0">Skills:</span>
                    <div className="flex flex-wrap gap-1">
                      {agent.skills.slice(0, 5).map(s => (
                        <span key={s.id} className="px-1.5 py-0.5 rounded bg-theme-interactive-primary/10 text-theme-info text-[10px] font-medium">
                          <EntityLink type="skill" id={s.id} label={s.name} className="text-theme-info" />
                        </span>
                      ))}
                      {agent.skills.length > 5 && (
                        <span className="text-theme-tertiary text-[10px]">+{agent.skills.length - 5} more</span>
                      )}
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* Column 2: Identity & System Prompt */}
            <div className="space-y-3">
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Identity</h4>
              <div className="space-y-2">
                {createdBy?.name && (
                  <DetailRow icon={User} label="Created by" value={createdBy.name} />
                )}
                <DetailRow icon={Clock} label="Created" value={timeAgo(agent.created_at)} />
                <DetailRow icon={Clock} label="Updated" value={timeAgo(agent.updated_at)} />
                {agent.system_prompt && (
                  <div className="pt-1">
                    <div className="flex items-center gap-1.5 mb-1.5">
                      <FileText className="h-3.5 w-3.5 text-theme-tertiary" />
                      <span className="text-xs text-theme-secondary">System Prompt</span>
                    </div>
                    <div className="bg-theme-background rounded-md px-3 py-2 max-h-24 overflow-y-auto">
                      <p className="text-[11px] text-theme-tertiary leading-relaxed whitespace-pre-wrap break-words">
                        {agent.system_prompt.length > 300
                          ? `${agent.system_prompt.slice(0, 300)}...`
                          : agent.system_prompt
                        }
                      </p>
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* Column 3: Performance */}
            <div className="space-y-3">
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Performance</h4>
              {hasExecutions && execStats ? (
                <>
                  {/* Success rate bar */}
                  <div>
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-xs text-theme-tertiary">Success Rate</span>
                      <span className={cn('text-xs font-semibold', successRateColor(execStats.success_rate || 0))}>
                        {execStats.success_rate ?? 0}%
                      </span>
                    </div>
                    <div className="h-1.5 bg-theme-background-secondary rounded-full overflow-hidden">
                      <div
                        className={cn(
                          'h-full rounded-full transition-all duration-500',
                          (execStats.success_rate || 0) >= 80 ? 'bg-theme-status-success' :
                          (execStats.success_rate || 0) >= 50 ? 'bg-theme-status-warning' :
                          'bg-theme-status-error'
                        )}
                        style={{ width: `${execStats.success_rate ?? 0}%` }}
                      />
                    </div>
                  </div>
                  {/* Stat grid */}
                  <div className="grid grid-cols-3 gap-2">
                    <div className="bg-theme-background rounded-md px-3 py-2">
                      <div className="text-sm font-semibold text-theme-primary">
                        {execStats.total_executions.toLocaleString()}
                      </div>
                      <div className="text-[10px] text-theme-tertiary">Total Runs</div>
                    </div>
                    <div className="bg-theme-background rounded-md px-3 py-2">
                      <div className="text-sm font-semibold text-theme-success">
                        {execStats.successful_executions || 0}
                      </div>
                      <div className="text-[10px] text-theme-tertiary">Succeeded</div>
                    </div>
                    <div className="bg-theme-background rounded-md px-3 py-2">
                      <div className={cn(
                        'text-sm font-semibold',
                        (execStats.failed_executions || 0) > 0 ? 'text-theme-error' : 'text-theme-primary'
                      )}>
                        {execStats.failed_executions || 0}
                      </div>
                      <div className="text-[10px] text-theme-tertiary">Failed</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-1 text-xs text-theme-tertiary">
                    <Clock className="h-3 w-3" />
                    <span>Avg: {formatDuration(execStats.avg_execution_time || 0)}</span>
                  </div>
                </>
              ) : (
                <p className="text-xs text-theme-tertiary italic">No executions yet</p>
              )}
            </div>
          </div>
        </div>
      </td>
    </tr>
  );
};

// Reusable detail row for icon + label + value
function DetailRow({ icon: Icon, label, value }: { icon: React.ElementType; label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2 text-xs">
      <Icon className="h-3.5 w-3.5 text-theme-tertiary flex-shrink-0" />
      <span className="text-theme-secondary">{label}:</span>
      <span className="text-theme-primary font-medium truncate">{value}</span>
    </div>
  );
}
