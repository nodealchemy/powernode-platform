import React from 'react';
import {
  ChevronRight,
  ChevronDown,
  Clock,
  Cpu,
  DollarSign
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { formatNodeType } from '@/shared/utils/workflowUtils';
import { StatusIcon } from './StatusIcon';
import type { NodeExecutionCardProps } from './types';

export const NodeExecutionCard: React.FC<NodeExecutionCardProps> = ({
  node,
  index,
  isLast,
  isExpanded,
  isInputExpanded,
  isOutputExpanded,
  isMetadataExpanded,
  liveDuration,
  onToggleExpansion,
  onToggleInput,
  onToggleOutput,
  onToggleMetadata,
  formatDuration,
  renderOutput,
  renderCopyButton,
  renderExpandableContent
}) => {
  const getBadgeVariant = (status: string) => {
    switch (status) {
      case 'completed': return 'success';
      case 'failed': return 'danger';
      case 'running': return 'info';
      case 'pending': return 'outline';
      case 'cancelled': return 'secondary';
      default: return 'secondary';
    }
  };

  return (
    <div className="relative">
      {/* Connection line */}
      {!isLast && (
        <div className="absolute left-4 top-10 bottom-0 w-0.5 bg-theme-border" />
      )}

      {/* Node Execution Card */}
      <div className="flex items-start gap-3">
        {/* Status Icon */}
        <div className="relative flex items-center justify-center w-8 h-8 rounded-full bg-theme-surface border-2 border-theme">
          <StatusIcon status={node.status} />
          {/* Debug indicator for development */}
          {process.env.NODE_ENV === 'development' && (
            <div
              className="absolute -top-1 -right-1 text-xs bg-theme-warning text-theme-warning-text px-1 rounded"
              title={`Status: ${node.status}`}
            >
              {node.status === 'completed' ? '✓' : node.status === 'failed' ? '✗' : node.status === 'running' ? '⏳' : '⭕'}
            </div>
          )}
        </div>

        {/* Node Details */}
        <div className="flex-1 border border-theme rounded-lg bg-theme-surface">
          <div
            className="p-2 cursor-pointer hover:bg-theme-hover/50 transition-colors"
            onClick={onToggleExpansion}
          >
            <div className="flex items-start justify-between">
              <div className="flex-1">
                <div className="flex items-center gap-2">
                  {isExpanded ? (
                    <ChevronDown className="h-3 w-3 text-theme-muted" />
                  ) : (
                    <ChevronRight className="h-3 w-3 text-theme-muted" />
                  )}
                  <h5 className="font-medium text-sm text-theme-primary">
                    {node.node?.name || `Node ${index + 1}`}
                  </h5>
                  <Badge variant="outline" size="sm">
                    {formatNodeType(node.node?.node_type || 'unknown')}
                  </Badge>
                </div>

                <div className="flex items-center gap-3 mt-1 text-xs text-theme-muted">
                  <span className="flex items-center gap-1">
                    <Clock className="h-3 w-3" />
                    {node.status === 'running' && liveDuration
                      ? `${formatDuration(liveDuration)} (live)`
                      : formatDuration(node.execution_time_ms || node.duration_ms)
                    }
                    {node.status === 'running' && liveDuration && (
                      <span className="animate-pulse text-theme-info">●</span>
                    )}
                  </span>
                  {node.tokens_used && (
                    <span className="flex items-center gap-1">
                      <Cpu className="h-3 w-3" />
                      {node.tokens_used} tokens
                    </span>
                  )}
                  {(node.cost || node.cost_usd) && ((node.cost || node.cost_usd) ?? 0) > 0 && (
                    <span className="flex items-center gap-1">
                      <DollarSign className="h-3 w-3" />
                      ${(node.cost || node.cost_usd || 0).toFixed(4)}
                    </span>
                  )}
                </div>
              </div>

              <Badge
                variant={getBadgeVariant(node.status)}
                size="sm"
              >
                {node.status}
              </Badge>
            </div>
          </div>

          {/* Expanded Content */}
          {isExpanded && (
            <div className="border-t border-theme p-3 space-y-3 text-sm">
              <>
                {/* Input Data */}
                {node.input_data && Object.keys(node.input_data).length > 0 && (
                <div>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onToggleInput();
                    }}
                    className="flex items-center gap-2 text-xs font-medium text-theme-muted hover:text-theme-primary mb-1"
                  >
                    {isInputExpanded ? (
                      <ChevronDown className="h-3 w-3" />
                    ) : (
                      <ChevronRight className="h-3 w-3" />
                    )}
                    Input Data
                  </button>
                  {isInputExpanded && (
                    <div className="relative bg-theme-code p-2 rounded border border-theme">
                      <div className="absolute top-1 right-1">
                        {renderCopyButton(JSON.stringify(node.input_data, null, 2))}
                      </div>
                      {renderExpandableContent(
                        JSON.stringify(node.input_data, null, 2),
                        'input'
                      )}
                    </div>
                  )}
                </div>
              )}

              {/* Output Data */}
              {node.output_data && (
                <div>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onToggleOutput();
                    }}
                    className="flex items-center gap-2 text-xs font-medium text-theme-muted hover:text-theme-primary mb-1"
                  >
                    {isOutputExpanded ? (
                      <ChevronDown className="h-3 w-3" />
                    ) : (
                      <ChevronRight className="h-3 w-3" />
                    )}
                    Output Data
                  </button>
                  {isOutputExpanded && (
                    <div className="bg-theme-code p-2 rounded border border-theme">
                      {renderOutput(node.output_data, node.status)}
                    </div>
                  )}
                </div>
              )}

              {/* Error Details */}
              {node.error_message && (
                <div className="bg-theme-error/10 border border-theme-error/20 rounded p-2">
                  <p className="text-xs font-medium text-theme-error mb-1">Error:</p>
                  <p className="text-xs text-theme-error">{node.error_message}</p>
                </div>
              )}

              {/* Metadata */}
              {node.metadata && Object.keys(node.metadata).length > 0 && (
                <div>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onToggleMetadata();
                    }}
                    className="flex items-center gap-2 text-xs font-medium text-theme-muted hover:text-theme-primary mb-1"
                  >
                    {isMetadataExpanded ? (
                      <ChevronDown className="h-3 w-3" />
                    ) : (
                      <ChevronRight className="h-3 w-3" />
                    )}
                    Metadata
                  </button>
                  {isMetadataExpanded && (
                    <div className="relative bg-theme-surface/50 p-2 rounded border border-theme">
                      <div className="absolute top-1 right-1">
                        {renderCopyButton(JSON.stringify(node.metadata, null, 2))}
                      </div>
                      <pre className="text-xs overflow-x-auto pr-8">
                        <code className="text-theme-muted">
                          {JSON.stringify(node.metadata, null, 2)}
                        </code>
                      </pre>
                    </div>
                  )}
                </div>
              )}
              </>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
