import React from 'react';
import { NodeProps } from '@xyflow/react';
import { FileText } from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { PromptTemplateNode as PromptTemplateNodeType } from '@/shared/types/workflow';

export const PromptTemplateNode: React.FC<NodeProps<PromptTemplateNodeType>> = ({
  data,
  selected
}) => {

  const getTemplateLabel = () => {
    switch (data.configuration?.templateType) {
      case 'conversation':
        return 'CHAT';
      case 'code':
        return 'CODE';
      case 'analysis':
        return 'ANALYSIS';
      case 'creative':
        return 'CREATIVE';
      default:
        return 'TEMPLATE';
    }
  };

  const getTemplatePreview = () => {
    const template = data.configuration?.template;
    if (!template) return 'No template content';

    return template.length > 40 ? `${template.substring(0, 40)}...` : template;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-prompt-template">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <FileText className="h-4 w-4" />
            <span className="font-medium text-sm">PROMPT</span>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Prompt Template'}
          </h3>
          {data.description && (
            <p className="text-sm text-theme-muted mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {data.configuration?.template && (
          <div className="p-2 bg-theme-background border border-theme-border rounded text-xs font-mono">
            <div className="text-theme-secondary line-clamp-2">
              {getTemplatePreview()}
            </div>
          </div>
        )}

        <div className="space-y-2 text-xs">
          {data.configuration?.templateType && (
            <div>
              <span className="text-theme-muted">Type:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {getTemplateLabel()}
              </span>
            </div>
          )}

          {data.configuration?.variables && data.configuration.variables.length > 0 && (
            <div>
              <span className="text-theme-muted">Variables:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {data.configuration.variables.length}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="prompt_template"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};