import React from 'react';
import { NodeProps } from '@xyflow/react';
import { ClipboardCheck, CheckCircle2, Clock, XCircle, Loader2 } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { GitCreateCheckNode as GitCreateCheckNodeType } from '@/shared/types/workflow';

export const GitCreateCheckNode: React.FC<NodeProps<GitCreateCheckNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getStatusIcon = () => {
    switch (data.configuration?.status) {
      case 'completed':
        return getConclusionIcon();
      case 'in_progress':
        return <Loader2 className="h-3 w-3 animate-spin" />;
      case 'queued':
        return <Clock className="h-3 w-3" />;
      default:
        return <Clock className="h-3 w-3" />;
    }
  };

  const getConclusionIcon = () => {
    switch (data.configuration?.conclusion) {
      case 'success':
        return <CheckCircle2 className="h-3 w-3" />;
      case 'failure':
      case 'timed_out':
        return <XCircle className="h-3 w-3" />;
      default:
        return <CheckCircle2 className="h-3 w-3" />;
    }
  };

  const getStatusColor = () => {
    if (data.configuration?.status === 'completed') {
      switch (data.configuration?.conclusion) {
        case 'success':
        case 'neutral':
        case 'skipped':
          return 'text-theme-success bg-theme-success/20';
        case 'failure':
        case 'cancelled':
        case 'timed_out':
        case 'action_required':
          return 'text-theme-danger bg-theme-danger/20';
        default:
          return 'text-theme-muted bg-theme-surface-alt';
      }
    }

    switch (data.configuration?.status) {
      case 'in_progress':
        return 'text-theme-warning bg-theme-warning/20';
      case 'queued':
        return 'text-theme-info bg-theme-info/20';
      default:
        return 'text-theme-muted bg-theme-surface-alt';
    }
  };

  const getStatusLabel = () => {
    if (data.configuration?.status === 'completed' && data.configuration?.conclusion) {
      return data.configuration.conclusion.toUpperCase().replace('_', ' ');
    }
    return data.configuration?.status?.toUpperCase().replace('_', ' ') || 'QUEUED';
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-indigo-500 to-indigo-600">
        <div className="flex items-center gap-2 text-white">
          <ClipboardCheck className="h-4 w-4" />
          <span className="font-medium text-sm">CREATE CHECK</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Create Check Run'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Status Badge */}
        <span className={`inline-flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-full ${getStatusColor()}`}>
          {getStatusIcon()}
          {getStatusLabel()}
        </span>

        {/* Check Name and Title */}
        <div className="space-y-1">
          {data.configuration?.name && (
            <div className="text-xs">
              <span className="text-theme-muted">Check:</span>
              <span className="ml-1 text-theme-secondary font-mono">
                {data.configuration.name}
              </span>
            </div>
          )}
          {data.configuration?.title && (
            <div className="text-xs">
              <span className="text-theme-muted">Title:</span>
              <span className="ml-1 text-theme-secondary">
                {data.configuration.title}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="git_create_check"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="git_create_check"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
