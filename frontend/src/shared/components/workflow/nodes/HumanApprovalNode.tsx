import React from 'react';
import { NodeProps } from '@xyflow/react';
import { UserCheck } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { HumanApprovalNode as HumanApprovalNodeType } from '@/shared/types/workflow';

export const HumanApprovalNode: React.FC<NodeProps<HumanApprovalNodeType>> = ({
  data,
  selected
}) => {

  const getApprovalLabel = () => {
    const config = data.configuration;
    if (!config) return 'Human Approval';

    const approverCount = config.approvers?.length || 0;
    
    switch (config.approvalType) {
      case 'all':
        return `All ${approverCount} approvers`;
      case 'majority':
        return `Majority of ${approverCount}`;
      case 'any':
      default:
        return `Any of ${approverCount || '?'} approvers`;
    }
  };

  const formatTimeout = () => {
    const hours = data.configuration?.timeoutHours;
    if (!hours) return null;
    
    if (hours < 24) {
      return `${hours}h timeout`;
    }
    const days = Math.floor(hours / 24);
    const remainingHours = hours % 24;
    
    if (remainingHours === 0) {
      return `${days}d timeout`;
    }
    return `${days}d ${remainingHours}h timeout`;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-human-approval">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <UserCheck className="h-4 w-4" />
            <span className="font-medium text-sm">APPROVAL</span>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Human Approval'}
          </h3>
          {data.description && (
            <p className="text-sm text-theme-muted mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        <div className="space-y-2 text-xs">
          <div>
            <span className="text-theme-muted">Type:</span>
            <span className="ml-2 text-theme-primary font-medium">
              {getApprovalLabel()}
            </span>
          </div>

          {formatTimeout() && (
            <div>
              <span className="text-theme-muted">Timeout:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {formatTimeout()}
              </span>
            </div>
          )}

          {data.configuration?.requireComment && (
            <div>
              <span className="text-theme-muted">Comment:</span>
              <span className="ml-2 text-node-human-approval font-medium">Required</span>
            </div>
          )}
        </div>
      </div>

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="human_approval"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};