import React from 'react';
import { NodeProps } from '@xyflow/react';
import { GitCommit, CheckCircle2, Clock, XCircle, AlertTriangle } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { GitCommitStatusNode as GitCommitStatusNodeType } from '@/shared/types/workflow';

export const GitCommitStatusNode: React.FC<NodeProps<GitCommitStatusNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getStateIcon = () => {
    switch (data.configuration?.state) {
      case 'success':
        return <CheckCircle2 className="h-3 w-3" />;
      case 'pending':
        return <Clock className="h-3 w-3" />;
      case 'failure':
        return <XCircle className="h-3 w-3" />;
      case 'error':
        return <AlertTriangle className="h-3 w-3" />;
      default:
        return <Clock className="h-3 w-3" />;
    }
  };

  const getStateColor = () => {
    switch (data.configuration?.state) {
      case 'success':
        return 'text-theme-success bg-theme-success/20';
      case 'pending':
        return 'text-theme-warning bg-theme-warning/20';
      case 'failure':
        return 'text-theme-danger bg-theme-danger/20';
      case 'error':
        return 'text-theme-danger bg-theme-danger/20';
      default:
        return 'text-theme-muted bg-theme-surface-alt';
    }
  };

  const truncateSha = (sha?: string) => {
    if (!sha) return null;
    return sha.length > 7 ? sha.substring(0, 7) : sha;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-purple-500 to-purple-600">
        <div className="flex items-center gap-2 text-white">
          <GitCommit className="h-4 w-4" />
          <span className="font-medium text-sm">COMMIT STATUS</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Update Commit Status'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* State Badge */}
        <span className={`inline-flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-full ${getStateColor()}`}>
          {getStateIcon()}
          {data.configuration?.state?.toUpperCase() || 'PENDING'}
        </span>

        {/* Context and SHA */}
        <div className="space-y-1">
          {data.configuration?.context && (
            <div className="text-xs">
              <span className="text-theme-muted">Context:</span>
              <span className="ml-1 text-theme-secondary font-mono">
                {data.configuration.context}
              </span>
            </div>
          )}
          {data.configuration?.sha && (
            <div className="text-xs">
              <span className="text-theme-muted">SHA:</span>
              <span className="ml-1 text-theme-secondary font-mono">
                {truncateSha(data.configuration.sha)}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="git_commit_status"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="git_commit_status"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
