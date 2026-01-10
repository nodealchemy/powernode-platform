import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Rocket, Server, RefreshCw, Layers } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { DeployNode as DeployNodeType } from '@/shared/types/workflow';

export const DeployNode: React.FC<NodeProps<DeployNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getEnvironmentColor = () => {
    switch (data.configuration?.environment) {
      case 'production':
        return 'bg-theme-danger/10 text-theme-danger';
      case 'staging':
        return 'bg-theme-warning/10 text-theme-warning';
      case 'development':
        return 'bg-theme-success/10 text-theme-success';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  };

  const getStrategyIcon = () => {
    switch (data.configuration?.strategy) {
      case 'rolling':
        return <RefreshCw className="h-3 w-3" />;
      case 'blue_green':
        return <Layers className="h-3 w-3" />;
      case 'canary':
        return <Server className="h-3 w-3" />;
      default:
        return <Rocket className="h-3 w-3" />;
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-rose-500 to-rose-600">
        <div className="flex items-center gap-2 text-white">
          <Rocket className="h-4 w-4" />
          <span className="font-medium text-sm">DEPLOY</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Deploy'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Environment Badge */}
        <span className={`inline-block text-xs font-bold px-2 py-0.5 rounded-full uppercase ${getEnvironmentColor()}`}>
          {data.configuration?.environment || data.configuration?.custom_environment || 'Unknown'}
        </span>

        {/* Strategy Info */}
        <div className="space-y-1">
          {data.configuration?.strategy && (
            <div className="flex items-center gap-1 text-xs">
              {getStrategyIcon()}
              <span className="text-theme-secondary capitalize">
                {data.configuration.strategy.replace('_', ' ')}
              </span>
            </div>
          )}
          {data.configuration?.replicas && (
            <div className="flex items-center gap-1 text-xs">
              <Server className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary">
                {data.configuration.replicas} replica(s)
              </span>
            </div>
          )}
          {data.configuration?.rollback_on_failure && (
            <span className="inline-block text-xs px-2 py-0.5 rounded-full bg-theme-warning/10 text-theme-warning">
              Auto-rollback
            </span>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="deploy"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="deploy"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
