import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Clock, CheckCircle2, XCircle, Loader2 } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { CiWaitStatusNode as CiWaitStatusNodeType } from '@/shared/types/workflow';

export const CiWaitStatusNode: React.FC<NodeProps<CiWaitStatusNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getStatusIcon = () => {
    switch (data.configuration?.expected_status) {
      case 'success':
        return <CheckCircle2 className="h-3 w-3 text-theme-success" />;
      case 'failure':
        return <XCircle className="h-3 w-3 text-theme-danger" />;
      case 'completed':
      case 'any':
        return <Loader2 className="h-3 w-3 text-theme-info" />;
      default:
        return <Clock className="h-3 w-3 text-theme-muted" />;
    }
  };

  const getStatusColor = () => {
    switch (data.configuration?.expected_status) {
      case 'success':
        return 'text-theme-success bg-theme-success/20';
      case 'failure':
        return 'text-theme-danger bg-theme-danger/20';
      case 'completed':
      case 'any':
        return 'text-theme-info bg-theme-info/20';
      default:
        return 'text-theme-muted bg-theme-surface-alt';
    }
  };

  const formatTimeout = (seconds?: number) => {
    if (!seconds) return null;
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
    return `${Math.floor(seconds / 3600)}h`;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-amber-500 to-amber-600">
        <div className="flex items-center gap-2 text-white">
          <Clock className="h-4 w-4" />
          <span className="font-medium text-sm">CI WAIT STATUS</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Wait for Pipeline'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Expected Status Badge */}
        <div className="flex items-center gap-2">
          <span className={`inline-flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-full ${getStatusColor()}`}>
            {getStatusIcon()}
            {data.configuration?.expected_status?.toUpperCase() || 'ANY'}
          </span>
        </div>

        {/* Timeout Info */}
        <div className="flex items-center gap-3 text-xs text-theme-secondary">
          {data.configuration?.timeout_seconds && (
            <div className="flex items-center gap-1">
              <Clock className="h-3 w-3 text-theme-muted" />
              <span>Timeout: {formatTimeout(data.configuration.timeout_seconds)}</span>
            </div>
          )}
          {data.configuration?.poll_interval_seconds && (
            <div className="flex items-center gap-1">
              <span>Poll: {data.configuration.poll_interval_seconds}s</span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="ci_wait_status"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="ci_wait_status"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
