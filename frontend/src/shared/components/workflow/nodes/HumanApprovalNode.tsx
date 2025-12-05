import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { User, UserCheck, Clock, AlertCircle } from 'lucide-react';

export const HumanApprovalNode: React.FC<NodeProps<any>> = ({ 
  data, 
  selected 
}) => {
  const getApprovalIcon = () => {
    const config = data.configuration;
    if (config?.timeoutHours && config.timeoutHours > 0) {
      return <Clock className="h-4 w-4" />;
    }
    if (config?.approvalType === 'all') {
      return <UserCheck className="h-4 w-4" />;
    }
    return <User className="h-4 w-4" />;
  };

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
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme-interactive-primary'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Input Handle - orientation-aware */}
      <Handle
        type="target"
        position={data.handleOrientation === 'horizontal' ? Position.Left : Position.Top}
        className="w-3 h-3 bg-theme-interactive-primary border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { left: -6 } : { top: -6 }}
      />

      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white">
          {getApprovalIcon()}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Human Approval'}
          </h3>
          <p className="text-xs text-theme-interactive-primary font-medium">
            {getApprovalLabel()}
          </p>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Configuration Details */}
      <div className="space-y-2">
        {formatTimeout() && (
          <div className="text-xs">
            <span className="text-theme-muted">Timeout:</span>
            <span className="ml-1 text-theme-secondary font-semibold">
              {formatTimeout()}
            </span>
          </div>
        )}

        {data.configuration?.requireComment && (
          <div className="text-xs">
            <span className="text-theme-muted">Comment:</span>
            <span className="ml-1 text-theme-interactive-primary font-semibold">Required</span>
          </div>
        )}

        {data.configuration?.escalationUsers && data.configuration.escalationUsers.length > 0 && (
          <div className="text-xs">
            <span className="text-theme-muted">Escalation:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.escalationUsers.length} users
            </span>
          </div>
        )}

        {data.configuration?.instructions && (
          <div className="text-xs">
            <span className="text-theme-muted">Instructions:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.instructions.length > 30 
                ? `${data.configuration.instructions.substring(0, 30)}...`
                : data.configuration.instructions
              }
            </span>
          </div>
        )}
      </div>

      {/* Status Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-2 h-2 bg-theme-interactive-primary rounded-full animate-pulse" />
      </div>

      {/* Warning for timeout */}
      {data.configuration?.timeoutHours && (
        <div className="absolute -top-1 -right-1">
          <AlertCircle className="h-3 w-3 text-amber-500" />
        </div>
      )}

      {/* Approved Output Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="approved"
        className="w-3 h-3 bg-theme-success border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6, top: '40%' } : { bottom: -6, left: '40%' }}
      />

      {/* Rejected Output Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="rejected"
        className="w-3 h-3 bg-theme-danger border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6, top: '60%' } : { bottom: -6, left: '60%' }}
      />
    </div>
  );
};