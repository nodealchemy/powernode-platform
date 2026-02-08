// Custom ReactFlow nodes for team execution diagram
import React from 'react';
import { Handle, Position, NodeTypes } from '@xyflow/react';
import { Bot, Crown, Play, Flag, CheckCircle, XCircle, Loader, Clock } from 'lucide-react';
import type { ExecutionMemberNodeData } from './executionDiagramTypes';

const statusBorderClass: Record<string, string> = {
  idle: 'border-theme opacity-60',
  running: 'border-theme-info execution-node-pulse',
  completed: 'border-theme-success',
  failed: 'border-theme-danger',
};

const statusIcon: Record<string, React.ReactNode> = {
  idle: <Clock className="h-3 w-3 text-theme-muted" />,
  running: <Loader className="h-3 w-3 text-theme-info animate-spin" />,
  completed: <CheckCircle className="h-3 w-3 text-theme-success" />,
  failed: <XCircle className="h-3 w-3 text-theme-danger" />,
};

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function ExecutionMemberNode({ data }: { data: ExecutionMemberNodeData }) {
  const borderClass = statusBorderClass[data.status] || statusBorderClass.idle;

  return (
    <div
      className={`px-4 py-3 rounded-lg border-2 bg-theme-surface shadow-lg min-w-[160px] max-w-[200px] ${borderClass}`}
    >
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <Handle type="target" position={Position.Left} id="left-target" className="!bg-theme-border" />
      <Handle type="source" position={Position.Bottom} className="!bg-theme-border" />
      <Handle type="source" position={Position.Right} id="right-source" className="!bg-theme-border" />

      <div className="flex items-center gap-2">
        {data.isLead ? (
          <Crown className="h-4 w-4 text-theme-warning flex-shrink-0" />
        ) : (
          <Bot className="h-4 w-4 text-theme-info flex-shrink-0" />
        )}
        <div className="flex-1 min-w-0">
          <div className="font-semibold text-theme-primary text-sm truncate">
            {data.memberName}
          </div>
          <div className="text-[10px] text-theme-tertiary truncate">{data.role}</div>
        </div>
        {statusIcon[data.status]}
      </div>

      {data.durationMs !== undefined && (
        <div className="text-[10px] text-theme-secondary mt-1">
          {formatDuration(data.durationMs)}
        </div>
      )}
    </div>
  );
}

function ExecutionInputNode({ data }: { data: ExecutionMemberNodeData }) {
  return (
    <div className="px-3 py-2 rounded-full border border-theme-info bg-theme-info/10 shadow min-w-[80px] flex items-center justify-center gap-1.5">
      <Handle type="source" position={Position.Bottom} className="!bg-theme-info" />
      <Handle type="source" position={Position.Right} id="right-source" className="!bg-theme-info" />
      <Play className="h-3.5 w-3.5 text-theme-info" />
      <span className="text-xs font-medium text-theme-info">{data.memberName}</span>
    </div>
  );
}

function ExecutionOutputNode({ data }: { data: ExecutionMemberNodeData }) {
  const colorMap: Record<string, { border: string; bg: string; text: string }> = {
    idle: { border: 'border-theme', bg: 'bg-theme-accent/50', text: 'text-theme-secondary' },
    running: { border: 'border-theme', bg: 'bg-theme-accent/50', text: 'text-theme-secondary' },
    completed: { border: 'border-theme-success', bg: 'bg-theme-success/10', text: 'text-theme-success' },
    failed: { border: 'border-theme-danger', bg: 'bg-theme-error/10', text: 'text-theme-danger' },
  };
  const colors = colorMap[data.status] || colorMap.idle;

  return (
    <div className={`px-3 py-2 rounded-full border ${colors.border} ${colors.bg} shadow min-w-[80px] flex items-center justify-center gap-1.5`}>
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <Handle type="target" position={Position.Left} id="left-target" className="!bg-theme-border" />
      <Flag className={`h-3.5 w-3.5 ${colors.text}`} />
      <span className={`text-xs font-medium ${colors.text}`}>{data.memberName}</span>
    </div>
  );
}

export const executionNodeTypes: NodeTypes = {
  executionMember: ExecutionMemberNode,
  executionInput: ExecutionInputNode,
  executionOutput: ExecutionOutputNode,
};
