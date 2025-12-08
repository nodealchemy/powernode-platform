import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { Shield, CheckCircle, XCircle, AlertTriangle, FileCheck, Hash } from 'lucide-react';

export const ValidatorNode: React.FC<NodeProps<any>> = ({
  data,
  selected
}) => {
  const getValidationIcon = () => {
    switch (data.configuration?.validationType) {
      case 'json-schema':
        return <FileCheck className="h-4 w-4" />;
      case 'regex':
        return <Hash className="h-4 w-4" />;
      case 'custom':
        return <Shield className="h-4 w-4" />;
      case 'email':
        return <CheckCircle className="h-4 w-4" />;
      default:
        return <Shield className="h-4 w-4" />;
    }
  };

  const getValidationColor = () => {
    switch (data.configuration?.validationType) {
      case 'json-schema':
        return 'text-theme-info bg-theme-info/20';
      case 'regex':
        return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
      case 'custom':
        return 'text-theme-warning bg-theme-warning/20';
      case 'email':
        return 'text-theme-success bg-theme-success/20';
      case 'url':
        return 'text-theme-info bg-theme-info/20';
      default:
        return 'text-theme-danger bg-theme-danger/20';
    }
  };

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

  const getFailureIcon = () => {
    switch (data.configuration?.onFailure) {
      case 'stop':
        return <XCircle className="h-3 w-3" />;
      case 'warn':
        return <AlertTriangle className="h-3 w-3" />;
      case 'continue':
        return <CheckCircle className="h-3 w-3" />;
      default:
        return <XCircle className="h-3 w-3" />;
    }
  };

  const getFailureColor = () => {
    switch (data.configuration?.onFailure) {
      case 'stop':
        return 'text-theme-danger';
      case 'warn':
        return 'text-theme-warning';
      case 'continue':
        return 'text-theme-success';
      default:
        return 'text-theme-danger';
    }
  };

  const getSchemaPreview = () => {
    const schema = data.configuration?.schema;
    if (!schema) return 'No validation schema';

    return schema.length > 30 ? `${schema.substring(0, 30)}...` : schema;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-rose-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-rose-500 rounded-lg flex items-center justify-center text-white">
          <Shield className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Data Validator'}
          </h3>
          <div className="flex items-center gap-2">
            {data.configuration?.validationType && (
              <span className={`
                text-xs font-medium px-2 py-0.5 rounded-full
                ${getValidationColor()}
              `}>
                {getValidationLabel()}
              </span>
            )}
            {data.configuration?.strict && (
              <span className="text-xs font-medium text-theme-danger">STRICT</span>
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

      {/* Schema Preview */}
      {data.configuration?.schema && (
        <div className="mb-3 p-2 bg-theme-background border border-theme-border rounded text-xs font-mono">
          <div className="text-theme-secondary">
            {getSchemaPreview()}
          </div>
        </div>
      )}

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        {data.configuration?.rules && data.configuration.rules.length > 0 && (
          <div>
            <span className="text-theme-muted">Rules:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.rules.length} rule{data.configuration.rules.length !== 1 ? 's' : ''}
            </span>
          </div>
        )}
        {data.configuration?.onFailure && (
          <div className="flex items-center gap-1">
            <span className="text-theme-muted">On failure:</span>
            <div className={`flex items-center gap-1 ${getFailureColor()}`}>
              {getFailureIcon()}
              <span className="text-xs font-medium">
                {data.configuration.onFailure}
              </span>
            </div>
          </div>
        )}
      </div>

      {/* Validation Type Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-rose-500/10 rounded-full flex items-center justify-center text-rose-600">
          {getValidationIcon()}
        </div>
      </div>

      {/* Processing Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-rose-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-rose-500 rounded-full animate-pulse" style={{ animationDelay: '100ms' }} />
          <div className="w-1 h-3 bg-rose-500 rounded-full animate-pulse" style={{ animationDelay: '200ms' }} />
        </div>
      </div>

      {/* Handles - orientation-aware */}
      <Handle
        type="target"
        position={data.handleOrientation === 'horizontal' ? Position.Left : Position.Top}
        className="w-3 h-3 bg-rose-500 border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { left: -6 } : { top: -6 }}
      />

      {/* Success Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="success"
        className="w-3 h-3 bg-theme-success border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6, top: '30%' } : { bottom: -6, left: '30%' }}
      />

      {/* Failure Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="failure"
        className="w-3 h-3 bg-theme-danger border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6, top: '70%' } : { bottom: -6, left: '70%' }}
      />
    </div>
  );
};