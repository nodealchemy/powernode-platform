import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { Database, Search, Plus, Edit3, Trash2, Copy } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';

export const DatabaseNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const getOperationIcon = () => {
    switch (data.configuration?.operation) {
      case 'select':
      case 'query':
        return <Search className="h-4 w-4" />;
      case 'insert':
        return <Plus className="h-4 w-4" />;
      case 'update':
        return <Edit3 className="h-4 w-4" />;
      case 'delete':
        return <Trash2 className="h-4 w-4" />;
      case 'backup':
        return <Copy className="h-4 w-4" />;
      default:
        return <Database className="h-4 w-4" />;
    }
  };

  const getOperationColor = () => {
    switch (data.configuration?.operation) {
      case 'select':
      case 'query':
        return 'text-theme-info bg-theme-info/20';
      case 'insert':
        return 'text-theme-success bg-theme-success/20';
      case 'update':
        return 'text-theme-warning bg-theme-warning/20';
      case 'delete':
        return 'text-theme-danger bg-theme-danger/20';
      case 'backup':
        return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
      default:
        return 'text-theme-info bg-theme-info/20';
    }
  };

  const getOperationLabel = () => {
    switch (data.configuration?.operation) {
      case 'select':
        return 'SELECT';
      case 'insert':
        return 'INSERT';
      case 'update':
        return 'UPDATE';
      case 'delete':
        return 'DELETE';
      case 'query':
        return 'QUERY';
      case 'backup':
        return 'BACKUP';
      default:
        return 'DB';
    }
  };

  const getQueryPreview = () => {
    const query = data.configuration?.query;
    if (!query) return 'No query specified';

    // Show first 40 characters
    return query.length > 40 ? `${query.substring(0, 40)}...` : query;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-indigo-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-indigo-500 rounded-lg flex items-center justify-center text-white">
          <Database className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Database Operation'}
          </h3>
          <div className="flex items-center gap-2">
            {data.configuration?.operation && (
              <span className={`
                text-xs font-medium px-2 py-0.5 rounded-full
                ${getOperationColor()}
              `}>
                {getOperationLabel()}
              </span>
            )}
            {data.configuration?.table && (
              <span className="text-xs text-theme-muted truncate">
                {data.configuration.table}
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

      {/* Query Preview */}
      {data.configuration?.query && (
        <div className="mb-3 p-2 bg-theme-background border border-theme-border rounded text-xs font-mono">
          <div className="text-theme-secondary">
            {getQueryPreview()}
          </div>
        </div>
      )}

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        {data.configuration?.timeout && (
          <div>
            <span className="text-theme-muted">Timeout:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.timeout}s
            </span>
          </div>
        )}
      </div>

      {/* Operation Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-indigo-500/10 rounded-full flex items-center justify-center text-indigo-600">
          {getOperationIcon()}
        </div>
      </div>

      {/* Processing Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-indigo-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-indigo-500 rounded-full animate-pulse" style={{ animationDelay: '100ms' }} />
          <div className="w-1 h-3 bg-indigo-500 rounded-full animate-pulse" style={{ animationDelay: '200ms' }} />
        </div>
      </div>

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="database"
        nodeColor="bg-indigo-500"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};