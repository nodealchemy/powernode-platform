import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { File, FileText, Download, Upload, FolderOpen, Archive, FileImage, FileVideo } from 'lucide-react';

export const FileNode: React.FC<NodeProps<any>> = ({
  data,
  selected
}) => {
  const getOperationIcon = () => {
    switch (data.configuration?.operation) {
      case 'read':
        return <FolderOpen className="h-4 w-4" />;
      case 'write':
      case 'create':
        return <Upload className="h-4 w-4" />;
      case 'download':
        return <Download className="h-4 w-4" />;
      case 'compress':
      case 'archive':
        return <Archive className="h-4 w-4" />;
      default:
        return <File className="h-4 w-4" />;
    }
  };

  const getFileTypeIcon = () => {
    switch (data.configuration?.fileType) {
      case 'text':
      case 'csv':
      case 'json':
        return <FileText className="h-4 w-4" />;
      case 'image':
        return <FileImage className="h-4 w-4" />;
      case 'video':
        return <FileVideo className="h-4 w-4" />;
      default:
        return <File className="h-4 w-4" />;
    }
  };

  const getOperationColor = () => {
    switch (data.configuration?.operation) {
      case 'read':
        return 'text-theme-info bg-theme-info/20';
      case 'write':
      case 'create':
        return 'text-theme-success bg-theme-success/20';
      case 'download':
        return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
      case 'compress':
      case 'archive':
        return 'text-theme-warning bg-theme-warning/20';
      default:
        return 'text-theme-muted bg-theme-surface';
    }
  };

  const getOperationLabel = () => {
    switch (data.configuration?.operation) {
      case 'read':
        return 'READ';
      case 'write':
        return 'WRITE';
      case 'create':
        return 'CREATE';
      case 'download':
        return 'DOWNLOAD';
      case 'compress':
        return 'COMPRESS';
      case 'archive':
        return 'ARCHIVE';
      default:
        return 'FILE';
    }
  };

  const getFilePathPreview = () => {
    const path = data.configuration?.filePath;
    if (!path) return 'No file path';

    // Show last part of path and beginning if too long
    const parts = path.split('/');
    const filename = parts[parts.length - 1];
    if (path.length <= 35) return path;

    return `.../${filename}`;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-slate-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-slate-500 rounded-lg flex items-center justify-center text-white">
          <File className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'File Operation'}
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
            {data.configuration?.fileType && (
              <span className="text-xs text-theme-muted">
                {data.configuration.fileType.toUpperCase()}
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

      {/* File Path Preview */}
      {data.configuration?.filePath && (
        <div className="mb-3 p-2 bg-theme-background border border-theme-border rounded text-xs font-mono">
          <div className="text-theme-secondary truncate">
            {getFilePathPreview()}
          </div>
        </div>
      )}

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        {data.configuration?.encoding && (
          <div>
            <span className="text-theme-muted">Encoding:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.encoding}
            </span>
          </div>
        )}
        {data.configuration?.format && (
          <div>
            <span className="text-theme-muted">Format:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.format}
            </span>
          </div>
        )}
      </div>

      {/* File Type Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-slate-500/10 rounded-full flex items-center justify-center text-slate-600">
          {getFileTypeIcon()}
        </div>
      </div>

      {/* Operation Icon Indicator */}
      <div className="absolute top-2 right-9">
        <div className="w-6 h-6 bg-slate-500/10 rounded-full flex items-center justify-center text-slate-600">
          {getOperationIcon()}
        </div>
      </div>

      {/* Processing Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-slate-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-slate-500 rounded-full animate-pulse" style={{ animationDelay: '100ms' }} />
          <div className="w-1 h-3 bg-slate-500 rounded-full animate-pulse" style={{ animationDelay: '200ms' }} />
        </div>
      </div>

      {/* Handles - orientation-aware */}
      <Handle
        type="target"
        position={data.handleOrientation === 'horizontal' ? Position.Left : Position.Top}
        className="w-3 h-3 bg-slate-500 border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { left: -6 } : { top: -6 }}
      />
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        className="w-3 h-3 bg-slate-500 border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6 } : { bottom: -6 }}
      />
    </div>
  );
};