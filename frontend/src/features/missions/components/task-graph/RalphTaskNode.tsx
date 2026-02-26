import React, { memo } from 'react';
import { Handle, Position } from '@xyflow/react';
import type { NodeProps } from '@xyflow/react';
import { Bot, Workflow, Server, Container, User, Globe, GitBranch } from 'lucide-react';

interface RalphTaskNodeData {
  task_key: string;
  description: string | null;
  status: string;
  execution_type: string;
  executor_name: string | null;
  phase: string | null;
}

const STATUS_COLORS: Record<string, string> = {
  pending: 'bg-theme-surface text-theme-tertiary border-theme-border',
  in_progress: 'bg-theme-accent/10 text-theme-accent border-theme-accent',
  passed: 'bg-theme-success/10 text-theme-success border-theme-success',
  failed: 'bg-theme-error/10 text-theme-error border-theme-error',
  blocked: 'bg-theme-warning/10 text-theme-warning border-theme-warning',
  skipped: 'bg-theme-surface text-theme-tertiary border-theme-border',
};

const EXEC_ICONS: Record<string, React.ElementType> = {
  agent: Bot,
  workflow: Workflow,
  pipeline: GitBranch,
  a2a_task: Globe,
  container: Container,
  human: User,
  community: Globe,
};

const RalphTaskNode: React.FC<NodeProps> = ({ data }) => {
  const nodeData = data as unknown as RalphTaskNodeData;
  const colorClass = STATUS_COLORS[nodeData.status] || STATUS_COLORS.pending;
  const Icon = EXEC_ICONS[nodeData.execution_type] || Server;

  return (
    <div className={`px-3 py-2 rounded-lg border min-w-[180px] max-w-[240px] ${colorClass}`}>
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <div className="flex items-center gap-2 mb-1">
        <Icon className="w-3.5 h-3.5 flex-shrink-0" />
        <span className="text-xs font-medium truncate">{nodeData.task_key}</span>
      </div>
      {nodeData.description && (
        <p className="text-[10px] opacity-75 line-clamp-2">{nodeData.description}</p>
      )}
      {nodeData.executor_name && (
        <p className="text-[10px] mt-1 opacity-60 truncate">{nodeData.executor_name}</p>
      )}
      <Handle type="source" position={Position.Bottom} className="!bg-theme-border" />
    </div>
  );
};

export default memo(RalphTaskNode);
