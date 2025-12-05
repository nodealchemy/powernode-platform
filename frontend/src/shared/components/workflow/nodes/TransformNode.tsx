import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { RotateCcw, Code, Filter, FileText } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';

export const TransformNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const getTransformIcon = () => {
    switch (data.configuration?.transformType) {
      case 'javascript':
        return <Code className="h-4 w-4" />;
      case 'jq':
        return <Filter className="h-4 w-4" />;
      case 'template':
        return <FileText className="h-4 w-4" />;
      default:
        return <RotateCcw className="h-4 w-4" />;
    }
  };

  const getTransformLabel = () => {
    switch (data.configuration?.transformType) {
      case 'javascript':
        return 'JavaScript';
      case 'jq':
        return 'JQ Query';
      case 'template':
        return 'Template';
      default:
        return 'Transform';
    }
  };

  const getTransformColor = () => {
    switch (data.configuration?.transformType) {
      case 'javascript':
        return 'text-theme-warning bg-yellow-100';
      case 'jq':
        return 'text-theme-info bg-blue-100';
      case 'template':
        return 'text-theme-success bg-green-100';
      default:
        return 'text-teal-600 bg-teal-100';
    }
  };

  const getCodePreview = () => {
    const code = data.configuration?.code;
    if (!code) return 'No transformation code';
    
    // Show first line or first 40 characters
    const firstLine = code.split('\n')[0];
    return firstLine.length > 40 ? `${firstLine.substring(0, 40)}...` : firstLine;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-teal-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-teal-500 rounded-lg flex items-center justify-center text-white">
          <RotateCcw className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Transform'}
          </h3>
          <div className="flex items-center gap-2">
            {data.configuration?.transformType && (
              <span className={`
                text-xs font-medium px-2 py-0.5 rounded-full
                ${getTransformColor()}
              `}>
                {getTransformLabel()}
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

      {/* Code Preview */}
      <div className="mb-3 p-2 bg-theme-background border border-theme-border rounded text-xs font-mono">
        <div className="text-theme-secondary">
          {getCodePreview()}
        </div>
      </div>

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        {data.configuration?.code && (
          <div>
            <span className="text-theme-muted">Lines:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.code.split('\n').length}
            </span>
          </div>
        )}
      </div>

      {/* Transform Type Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-teal-500/10 rounded-full flex items-center justify-center text-teal-600">
          {getTransformIcon()}
        </div>
      </div>

      {/* Processing Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-teal-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-teal-500 rounded-full animate-pulse" style={{ animationDelay: '100ms' }} />
          <div className="w-1 h-3 bg-teal-500 rounded-full animate-pulse" style={{ animationDelay: '200ms' }} />
        </div>
      </div>

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="transform"
        nodeColor="bg-teal-500"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};