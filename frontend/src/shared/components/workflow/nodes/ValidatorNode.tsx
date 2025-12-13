import React from 'react';
import { NodeProps } from '@xyflow/react';
import { CheckCircle } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { ValidatorNode as ValidatorNodeType } from '@/shared/types/workflow';

export const ValidatorNode: React.FC<NodeProps<ValidatorNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getValidationLabel = () => {
    switch (data.configuration?.validationType) {
      case 'json-schema':
        return 'JSON Schema';
      case 'regex':
        return 'Regex';
      case 'custom':
        return 'Custom';
      case 'email':
        return 'Email';
      case 'url':
        return 'URL';
      default:
        return 'Validation';
    }
  };

  const getSchemaPreview = () => {
    const schema = data.configuration?.schema;
    if (!schema) return 'No validation schema';

    return schema.length > 30 ? `${schema.substring(0, 30)}...` : schema;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-validator">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <CheckCircle className="h-4 w-4" />
            <span className="font-medium text-sm">VALIDATOR</span>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Data Validator'}
          </h3>
          {data.description && (
            <p className="text-sm text-theme-muted mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {data.configuration?.schema && (
          <div className="p-2 bg-theme-background border border-theme-border rounded text-xs font-mono">
            <div className="text-theme-secondary line-clamp-2">
              {getSchemaPreview()}
            </div>
          </div>
        )}

        <div className="space-y-2 text-xs">
          {data.configuration?.validationType && (
            <div>
              <span className="text-theme-muted">Type:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {getValidationLabel()}
              </span>
            </div>
          )}

          {data.configuration?.rules && data.configuration.rules.length > 0 && (
            <div>
              <span className="text-theme-muted">Rules:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {data.configuration.rules.length}
              </span>
            </div>
          )}

          {data.configuration?.onFailure && (
            <div>
              <span className="text-theme-muted">On failure:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {data.configuration.onFailure}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="validator"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="validator"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};