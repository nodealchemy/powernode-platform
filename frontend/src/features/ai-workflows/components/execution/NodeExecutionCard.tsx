import React from 'react';
import {
  ChevronRight,
  ChevronDown,
  Clock,
  CheckCircle,
  XCircle,
  AlertCircle,
  Activity,
  FileText,
  Code,
  ArrowRight,
  Cpu,
  DollarSign
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { AiWorkflowNodeExecution } from '@/shared/types/workflow';
import { formatNodeType } from '@/shared/utils/workflow';
import { formatDuration } from './executionUtils';
import { EnhancedCopyButton } from './EnhancedCopyButton';

interface NodeExecutionCardProps {
  node: AiWorkflowNodeExecution;
  index: number;
  isLast: boolean;
  isExpanded: boolean;
  isInputExpanded: boolean;
  isOutputExpanded: boolean;
  isMetadataExpanded: boolean;
  liveDuration?: number;
  onToggle: () => void;
  onToggleInput: () => void;
  onToggleOutput: () => void;
  onToggleMetadata: () => void;
  onCopy: (text: string, format: string) => void;
}

const renderStatusIcon = (status: string) => {
  switch (status) {
    case 'completed':
      return <CheckCircle className="h-4 w-4 text-theme-success" />;
    case 'failed':
      return <XCircle className="h-4 w-4 text-theme-error" />;
    case 'running':
      return <Activity className="h-4 w-4 text-theme-info animate-pulse" />;
    case 'cancelled':
      return <AlertCircle className="h-4 w-4 text-theme-warning" />;
    case 'pending':
      return <Clock className="h-4 w-4 text-theme-muted" />;
    default:
      return <AlertCircle className="h-4 w-4 text-theme-muted" />;
  }
};

const renderExpandableContent = (
  data: unknown,
  isExpanded: boolean,
  onToggle: () => void,
  onCopy: (text: string, format: string) => void,
  maxLines: number = 6
) => {
  const dataStr = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
  const lines = dataStr.split('\n');
  const shouldShowToggle = lines.length > maxLines || dataStr.length > 300;
  const displayLines = isExpanded ? lines : lines.slice(0, maxLines);
  const displayText = displayLines.join('\n');

  return (
    <div className="relative">
      <pre className={`text-xs bg-theme-code rounded border border-theme break-words whitespace-pre-wrap ${
        isExpanded ? 'max-h-[500px] overflow-auto custom-scrollbar p-2' : 'max-h-24 overflow-hidden pt-2 px-2 pb-2'
      }`}>
        <code className="text-theme-code-text">
          {displayText}
          {!isExpanded && shouldShowToggle && lines.length > maxLines && '...'}
        </code>
      </pre>
      {shouldShowToggle && (
        <div className="mt-2 flex items-center justify-between">
          <Button
            size="sm"
            variant="ghost"
            onClick={onToggle}
            className="text-xs text-theme-interactive-primary hover:text-theme-interactive-primary/80 p-1 h-auto"
          >
            {isExpanded ? 'Collapse' : `Expand complete content (${lines.length} lines)`}
          </Button>
          <EnhancedCopyButton data={data} onCopy={onCopy} />
        </div>
      )}
      {!shouldShowToggle && (
        <div className="absolute top-2 right-2">
          <EnhancedCopyButton data={data} onCopy={onCopy} />
        </div>
      )}
      {isExpanded && shouldShowToggle && (
        <div className="text-xs text-theme-muted mt-1">
          Showing complete content - scroll to view all
        </div>
      )}
    </div>
  );
};

export const NodeExecutionCard: React.FC<NodeExecutionCardProps> = ({
  node,
  index,
  isLast,
  isExpanded,
  isInputExpanded,
  isOutputExpanded,
  isMetadataExpanded,
  liveDuration,
  onToggle,
  onToggleInput,
  onToggleOutput,
  onToggleMetadata,
  onCopy
}) => {
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
          {renderStatusIcon(node.status)}
          {process.env.NODE_ENV === 'development' && (
            <div className="absolute -top-1 -right-1 text-xs bg-theme-warning text-theme-warning-text px-1 rounded" title={`Status: ${node.status}`}>
              {node.status === 'completed' ? '✓' : node.status === 'failed' ? '✗' : node.status === 'running' ? '⏳' : '⭕'}
            </div>
          )}
        </div>

        {/* Node Details */}
        <div className="flex-1 border border-theme rounded-lg bg-theme-surface">
          <div
            className="p-2 cursor-pointer hover:bg-theme-hover/50 transition-colors"
            onClick={onToggle}
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
                variant={
                  node.status === 'completed' ? 'success' :
                  node.status === 'failed' ? 'danger' :
                  node.status === 'running' ? 'info' :
                  node.status === 'pending' ? 'outline' :
                  node.status === 'cancelled' ? 'secondary' :
                  'secondary'
                }
                size="sm"
              >
                {node.status}
              </Badge>
            </div>
          </div>

          {/* Expanded Node Details */}
          {isExpanded && (
            // @ts-expect-error React 19 types strict children check
            <div className="border-t border-theme px-2 pb-1 space-y-1">
              {/* Input */}
              {node.input_data && (
                <div className="mt-2">
                  <p className="text-xs text-theme-muted mb-2 flex items-center gap-1">
                    <ArrowRight className="h-3 w-3" />
                    Input:
                  </p>
                  {renderExpandableContent(
                    node.input_data,
                    isInputExpanded,
                    onToggleInput,
                    onCopy,
                    6
                  )}
                </div>
              )}

              {/* Output */}
              {node.output_data && (
                <div>
                  <p className="text-xs text-theme-muted mb-2 flex items-center gap-1">
                    <FileText className="h-3 w-3" />
                    Output:
                  </p>
                  {renderExpandableContent(
                    node.output_data,
                    isOutputExpanded,
                    onToggleOutput,
                    onCopy,
                    6
                  )}
                </div>
              )}

              {/* Error - only show for failed nodes */}
              {node.error_details && node.status === 'failed' && (
                <div>
                  <p className="text-xs text-theme-error mb-1 flex items-center gap-1">
                    <XCircle className="h-3 w-3" />
                    Error:
                  </p>
                  <div className="bg-theme-error/10 border border-theme-error/20 rounded p-2">
                    <p className="text-xs text-theme-error">
                      {node.error_details.message || 'Node execution failed'}
                    </p>
                    {node.error_details.stack && (
                      <pre className="text-xs mt-1 overflow-x-auto">
                        <code>{node.error_details.stack}</code>
                      </pre>
                    )}
                  </div>
                </div>
              )}

              {/* Metadata */}
              {node.metadata && Object.keys(node.metadata).length > 0 && (
                <div>
                  <p className="text-xs text-theme-muted mb-2 flex items-center gap-1">
                    <Code className="h-3 w-3" />
                    Metadata:
                  </p>
                  {renderExpandableContent(
                    node.metadata,
                    isMetadataExpanded,
                    onToggleMetadata,
                    onCopy,
                    6
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
