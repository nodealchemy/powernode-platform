import React, { useState, useEffect, useCallback } from 'react';
import {
  ChevronRight,
  ChevronDown,
  Clock,
  Activity,
  Download,
  Eye,
  DollarSign,
  Timer,
  Loader2,
  Trash2,
  GitBranch
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { AiWorkflowRun, WorkflowRunStatus } from '@/shared/types/workflow';
import { formatDuration } from './executionUtils';

interface ExecutionHeaderProps {
  currentRun: AiWorkflowRun;
  runStatus: WorkflowRunStatus;
  isExpanded: boolean;
  isConnected: boolean;
  lastUpdateReceived: number | null;
  onToggle: () => void;
  onRefresh: () => void;
  onPreviewClick: () => void;
  onDeleteClick: () => void;
  onDownloadFromServer: (format: 'json' | 'txt' | 'markdown') => void;
  onExportExecution: () => void;
}

export const ExecutionHeader: React.FC<ExecutionHeaderProps> = ({
  currentRun,
  runStatus,
  isExpanded,
  isConnected,
  lastUpdateReceived,
  onToggle,
  onRefresh,
  onPreviewClick,
  onDeleteClick,
  onDownloadFromServer,
  onExportExecution
}) => {
  const [showDownloadMenu, setShowDownloadMenu] = useState(false);

  // Close download menu on click outside
  useEffect(() => {
    const handleClickOutside = () => {
      if (showDownloadMenu) setShowDownloadMenu(false);
    };

    if (showDownloadMenu) {
      document.addEventListener('click', handleClickOutside);
      return () => document.removeEventListener('click', handleClickOutside);
    }
  }, [showDownloadMenu]);

  const handleDownload = useCallback((format: 'json' | 'txt' | 'markdown') => {
    setShowDownloadMenu(false);
    onDownloadFromServer(format);
  }, [onDownloadFromServer]);

  const handleExport = useCallback(() => {
    setShowDownloadMenu(false);
    onExportExecution();
  }, [onExportExecution]);

  const isRunning = runStatus === 'running' || runStatus === 'initializing';

  return (
    <div className="flex items-start justify-between p-4 hover:bg-theme-surface/50 transition-colors">
      <div className="flex-1">
        <div className="flex items-center gap-3">
          <button
            onClick={(e) => { e.stopPropagation(); onToggle(); }}
            className="cursor-pointer hover:bg-theme-surface rounded p-0.5 transition-colors"
            aria-label={isExpanded ? "Collapse execution details" : "Expand execution details"}
          >
            {isExpanded ? (
              <ChevronDown className="h-4 w-4 text-theme-muted transition-transform duration-200" />
            ) : (
              <ChevronRight className="h-4 w-4 text-theme-muted transition-transform duration-200" />
            )}
          </button>
          <h4 className="font-medium text-theme-primary">
            Run #{(currentRun.run_id || currentRun.id)?.slice(-8)}
          </h4>
          <Badge
            variant={
              runStatus === 'completed' ? 'success' :
              runStatus === 'failed' ? 'danger' :
              runStatus === 'cancelled' ? 'secondary' :
              runStatus === 'running' ? 'info' :
              runStatus === 'initializing' ? 'warning' :
              runStatus === 'waiting_approval' ? 'warning' :
              'secondary'
            }
            size="sm"
          >
            {runStatus}
          </Badge>
          {isRunning && (
            <Loader2 className="h-3 w-3 animate-spin text-theme-info" />
          )}
          {isConnected && isRunning && (
            <div className="flex items-center gap-1 text-theme-success text-xs">
              <div className="animate-pulse h-2 w-2 bg-theme-success rounded-full" />
              Live
              {lastUpdateReceived && (
                <span className="text-theme-muted ml-1">
                  (Updated {new Date(lastUpdateReceived).toLocaleTimeString()})
                </span>
              )}
            </div>
          )}
        </div>

        <div className="flex items-center gap-4 mt-1 text-sm text-theme-muted">
          <span className="flex items-center gap-1">
            <Clock className="h-3 w-3" />
            {new Date(currentRun.started_at || currentRun.created_at).toLocaleString()}
          </span>
          <span className="flex items-center gap-1">
            <Timer className="h-3 w-3" />
            {formatDuration((currentRun.duration_seconds || 0) * 1000)}
          </span>
          <span className="flex items-center gap-1">
            <GitBranch className="h-3 w-3" />
            Progress: {currentRun.completed_nodes || 0}/{currentRun.total_nodes || 0}
          </span>
          {currentRun.cost_usd && currentRun.cost_usd > 0 && (
            <span className="flex items-center gap-1">
              <DollarSign className="h-3 w-3" />
              ${currentRun.cost_usd.toFixed(4)}
            </span>
          )}
        </div>
      </div>

      <div className="flex items-center gap-2">
        {/* Download Menu */}
        <div className="relative">
          <Button
            size="sm"
            variant="ghost"
            onClick={(e) => { e.stopPropagation(); setShowDownloadMenu(!showDownloadMenu); }}
            className="p-2"
            title="Download workflow output"
          >
            <Download className="h-4 w-4" />
          </Button>
          {showDownloadMenu && (
            <div className="absolute top-full left-0 mt-1 bg-theme-surface border border-theme rounded-md shadow-lg z-50 min-w-[160px]">
              <div className="p-2">
                <p className="text-xs text-theme-muted mb-2 font-medium">Download Format:</p>
                <div className="space-y-1">
                  <button onClick={(e) => { e.stopPropagation(); handleDownload('json'); }}
                    className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary">
                    JSON (structured data)
                  </button>
                  <button onClick={(e) => { e.stopPropagation(); handleDownload('txt'); }}
                    className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary">
                    Text (readable format)
                  </button>
                  <button onClick={(e) => { e.stopPropagation(); handleDownload('markdown'); }}
                    className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-primary">
                    Markdown (formatted)
                  </button>
                  <hr className="my-1 border-theme" />
                  <button onClick={(e) => { e.stopPropagation(); handleExport(); }}
                    className="w-full text-left px-2 py-1 text-xs rounded hover:bg-theme-hover text-theme-muted">
                    Export Execution Details
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>

        <Button
          size="sm"
          variant="ghost"
          onClick={(e) => { e.stopPropagation(); onPreviewClick(); }}
          className="p-2"
          title="Preview workflow output"
        >
          <Eye className="h-4 w-4" />
        </Button>

        <Button
          size="sm"
          variant="ghost"
          onClick={(e) => { e.stopPropagation(); onRefresh(); }}
          className="p-2"
          title="Refresh execution details"
        >
          <Activity className="h-4 w-4" />
        </Button>

        <Button
          size="sm"
          variant="ghost"
          onClick={(e) => {
            e.stopPropagation();
            onDeleteClick();
          }}
          className={`p-2 ${isRunning ? 'text-theme-muted opacity-50 cursor-not-allowed' : 'text-theme-destructive hover:bg-theme-destructive/10'}`}
          title={isRunning ? 'Cannot delete while execution is running' : 'Delete execution'}
          disabled={isRunning}
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
};
