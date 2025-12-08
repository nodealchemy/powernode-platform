import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { FileText, Variable, Shuffle, Eye, Code2, MessageSquare } from 'lucide-react';

export const PromptTemplateNode: React.FC<NodeProps<any>> = ({
  data,
  selected
}) => {
  const getTemplateIcon = () => {
    switch (data.configuration?.templateType) {
      case 'conversation':
        return <MessageSquare className="h-4 w-4" />;
      case 'code':
        return <Code2 className="h-4 w-4" />;
      case 'analysis':
        return <Eye className="h-4 w-4" />;
      case 'creative':
        return <Shuffle className="h-4 w-4" />;
      default:
        return <FileText className="h-4 w-4" />;
    }
  };

  const getTemplateColor = () => {
    switch (data.configuration?.templateType) {
      case 'conversation':
        return 'text-theme-info bg-theme-info/20';
      case 'code':
        return 'text-theme-success bg-theme-success/20';
      case 'analysis':
        return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
      case 'creative':
        return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
      default:
        return 'text-theme-warning bg-theme-warning/20';
    }
  };

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
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-amber-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-amber-500 rounded-lg flex items-center justify-center text-white">
          <FileText className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Prompt Template'}
          </h3>
          <div className="flex items-center gap-2">
            {data.configuration?.templateType && (
              <span className={`
                text-xs font-medium px-2 py-0.5 rounded-full
                ${getTemplateColor()}
              `}>
                {getTemplateLabel()}
              </span>
            )}
            {data.configuration?.version && (
              <span className="text-xs text-theme-muted">
                v{data.configuration.version}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Template Preview */}
      {data.configuration?.template && (
        <div className="mb-3 p-2 bg-theme-background border border-theme-border rounded text-xs font-mono">
          <div className="text-theme-secondary">
            {getTemplatePreview()}
          </div>
        </div>
      )}

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        {data.configuration?.variables && data.configuration.variables.length > 0 && (
          <div className="flex items-center gap-1">
            <Variable className="h-3 w-3 text-theme-muted" />
            <span className="text-theme-muted">Variables:</span>
            <span className="text-theme-secondary">
              {data.configuration.variables.length} variable{data.configuration.variables.length !== 1 ? 's' : ''}
            </span>
          </div>
        )}
        {data.configuration?.category && (
          <div>
            <span className="text-theme-muted">Category:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.category}
            </span>
          </div>
        )}
        {data.configuration?.testMode && (
          <div className="flex items-center gap-1">
            <Eye className="h-3 w-3 text-theme-warning" />
            <span className="text-theme-warning font-medium">TEST MODE</span>
          </div>
        )}
      </div>

      {/* Template Type Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-amber-500/10 rounded-full flex items-center justify-center text-amber-600">
          {getTemplateIcon()}
        </div>
      </div>

      {/* Processing Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-amber-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-amber-500 rounded-full animate-pulse" style={{ animationDelay: '100ms' }} />
          <div className="w-1 h-3 bg-amber-500 rounded-full animate-pulse" style={{ animationDelay: '200ms' }} />
        </div>
      </div>

      {/* Handles - orientation-aware */}
      <Handle
        type="target"
        position={data.handleOrientation === 'horizontal' ? Position.Left : Position.Top}
        className="w-3 h-3 bg-amber-500 border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { left: -6 } : { top: -6 }}
      />
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        className="w-3 h-3 bg-amber-500 border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6 } : { bottom: -6 }}
      />
    </div>
  );
};