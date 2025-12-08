import React from 'react';
import { NodeProps } from '@xyflow/react';
import { GitBranch, Equal, X, ChevronUp, ChevronDown, Search } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';

export const ConditionNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();
  const getConditionIcon = () => {
    switch (data.configuration?.conditionType) {
      case 'equals':
        return <Equal className="h-4 w-4" />;
      case 'not_equals':
        return <X className="h-4 w-4" />;
      case 'greater_than':
        return <ChevronUp className="h-4 w-4" />;
      case 'less_than':
        return <ChevronDown className="h-4 w-4" />;
      case 'contains':
      case 'regex':
        return <Search className="h-4 w-4" />;
      default:
        return <GitBranch className="h-4 w-4" />;
    }
  };

  const getConditionLabel = () => {
    switch (data.configuration?.conditionType) {
      case 'equals':
        return 'Equals';
      case 'not_equals':
        return 'Not Equals';
      case 'greater_than':
        return 'Greater Than';
      case 'less_than':
        return 'Less Than';
      case 'contains':
        return 'Contains';
      case 'regex':
        return 'Regex Match';
      default:
        return 'Condition';
    }
  };

  const getConditionExpression = () => {
    const { variablePath, conditionType, expectedValue } = data.configuration || {};

    if (!variablePath || !conditionType || !expectedValue) {
      return 'Configure condition';
    }

    const operatorMap: Record<string, string> = {
      equals: '==',
      not_equals: '!=',
      greater_than: '>',
      less_than: '<',
      contains: 'contains',
      regex: 'matches'
    };
    const operator = operatorMap[conditionType] || '?';

    return `${variablePath} ${operator} ${expectedValue}`;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-52 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme-warning'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-theme-warning rounded-lg flex items-center justify-center text-white">
          <GitBranch className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Condition'}
          </h3>
          <p className="text-xs text-theme-warning font-medium">
            {getConditionLabel()}
          </p>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Condition Expression */}
      <div className="mb-3 p-2 bg-theme-warning/10 border border-theme-warning/30 rounded text-xs font-mono">
        <div className="text-theme-warning">
          {getConditionExpression()}
        </div>
      </div>

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        {data.configuration?.variablePath && (
          <div>
            <span className="text-theme-muted">Variable:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {data.configuration.variablePath}
            </span>
          </div>
        )}

        {data.configuration?.expectedValue && (
          <div>
            <span className="text-theme-muted">Expected:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.expectedValue.length > 20 
                ? `${data.configuration.expectedValue.substring(0, 20)}...`
                : data.configuration.expectedValue
              }
            </span>
          </div>
        )}
      </div>

      {/* Condition Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-theme-warning/10 rounded-full flex items-center justify-center text-theme-warning">
          {getConditionIcon()}
        </div>
      </div>

      {/* Branch Indicators */}
      <div className="absolute bottom-2 right-2 flex gap-1">
        <div className="w-2 h-2 bg-theme-success rounded-full" title="True path" />
        <div className="w-2 h-2 bg-theme-danger rounded-full" title="False path" />
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="condition"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false} // Could be based on condition evaluation
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles for Condition Node */}
      <DynamicNodeHandles
        nodeType="condition"
        nodeColor="bg-theme-warning"
        orientation={data?.handleOrientation || 'vertical'}
      />

      {/* Path Labels */}
      <div className="absolute bottom-2 left-1/2 transform -translate-x-1/2 flex gap-4 text-xs font-medium">
        <div className="text-theme-success">T</div>
        <div className="text-theme-danger">F</div>
      </div>
    </div>
  );
};