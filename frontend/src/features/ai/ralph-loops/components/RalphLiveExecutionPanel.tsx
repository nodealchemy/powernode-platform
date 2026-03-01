import React, { useRef, useEffect, useState } from 'react';
import { Activity, CheckCircle2, XCircle, ChevronDown, ChevronUp, Clock } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardContent } from '@/shared/components/ui/Card';
import type { RalphIteration } from '@/shared/services/ai/types/ralph-types';

interface RalphLiveExecutionPanelProps {
  iterations: RalphIteration[];
  isRunning: boolean;
}

export const RalphLiveExecutionPanel: React.FC<RalphLiveExecutionPanelProps> = ({
  iterations,
  isRunning,
}) => {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  // Auto-scroll to latest entry
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [iterations.length]);

  const toggleExpand = (id: string) => {
    setExpandedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  };

  const formatDuration = (ms?: number) => {
    if (!ms) return '-';
    if (ms < 1000) return `${ms}ms`;
    const seconds = Math.round(ms / 1000);
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes}m ${remainingSeconds}s`;
  };

  const truncateOutput = (text?: string, maxLength = 300) => {
    if (!text) return '';
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + '...';
  };

  if (iterations.length === 0 && !isRunning) return null;

  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <Activity className="w-4 h-4 text-theme-brand-primary" />
            <span className="text-sm font-semibold text-theme-text-primary">Live Execution</span>
          </div>
          {isRunning && (
            <Badge variant="info" size="sm">
              <span className="inline-block w-2 h-2 rounded-full bg-current mr-1.5 animate-pulse" />
              Running
            </Badge>
          )}
          {!isRunning && iterations.length > 0 && (
            <Badge variant="outline" size="sm">
              {iterations.length} iteration{iterations.length !== 1 ? 's' : ''}
            </Badge>
          )}
        </div>

        {iterations.length === 0 ? (
          <div className="text-sm text-theme-text-secondary py-2">
            Waiting for iteration results...
          </div>
        ) : (
          <div
            ref={scrollRef}
            className="space-y-2 max-h-64 overflow-y-auto pr-1"
          >
            {iterations.map((iteration) => {
              const isExpanded = expandedIds.has(iteration.id);
              const isSuccess = iteration.status === 'completed';
              const isFailed = iteration.status === 'failed';

              return (
                <div
                  key={iteration.id}
                  className="rounded-lg border border-theme-border bg-theme-bg-primary p-3"
                >
                  <div
                    className="flex items-center justify-between cursor-pointer"
                    onClick={() => toggleExpand(iteration.id)}
                  >
                    <div className="flex items-center gap-2">
                      {isSuccess && <CheckCircle2 className="w-4 h-4 text-theme-status-success" />}
                      {isFailed && <XCircle className="w-4 h-4 text-theme-status-error" />}
                      {!isSuccess && !isFailed && <Clock className="w-4 h-4 text-theme-text-secondary" />}
                      <span className="text-sm font-medium text-theme-text-primary">
                        #{iteration.iteration_number}
                      </span>
                      {iteration.task_key && (
                        <span className="text-xs text-theme-text-secondary">
                          {iteration.task_key}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-theme-text-secondary">
                        {formatDuration(iteration.duration_ms)}
                      </span>
                      {isExpanded ? (
                        <ChevronUp className="w-3.5 h-3.5 text-theme-text-secondary" />
                      ) : (
                        <ChevronDown className="w-3.5 h-3.5 text-theme-text-secondary" />
                      )}
                    </div>
                  </div>

                  {!isExpanded && iteration.ai_output && (
                    <p className="text-xs text-theme-text-secondary mt-1.5 line-clamp-2">
                      {truncateOutput(iteration.ai_output, 150)}
                    </p>
                  )}

                  {isExpanded && (
                    <div className="mt-2 space-y-2">
                      {iteration.ai_output && (
                        <pre className="text-xs text-theme-text-secondary bg-theme-bg-secondary rounded p-2 whitespace-pre-wrap max-h-48 overflow-y-auto">
                          {iteration.ai_output}
                        </pre>
                      )}
                      {iteration.error_message && (
                        <div className="text-xs text-theme-status-error bg-theme-status-error/10 rounded p-2">
                          {iteration.error_message}
                        </div>
                      )}
                      {iteration.git_commit_sha && (
                        <div className="text-xs text-theme-text-secondary">
                          Commit: <code className="bg-theme-bg-secondary px-1 rounded">{iteration.git_commit_sha.substring(0, 8)}</code>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
};
