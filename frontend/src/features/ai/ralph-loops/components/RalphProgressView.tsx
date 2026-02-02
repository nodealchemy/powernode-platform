import React, { useState, useEffect } from 'react';
import {
  BookOpen,
  GitCommit,
  RefreshCw,
  Lightbulb,
  FileText,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
import { cn } from '@/shared/utils/cn';
import type { RalphProgress } from '@/shared/services/ai/types/ralph-types';

interface RalphProgressViewProps {
  loopId: string;
  className?: string;
}

export const RalphProgressView: React.FC<RalphProgressViewProps> = ({
  loopId,
  className,
}) => {
  const [progress, setProgress] = useState<RalphProgress | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadProgress = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await ralphLoopsApi.getProgress(loopId);
      setProgress(response);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to load progress');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadProgress();
  }, [loopId]);

  if (loading) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-4 rounded-lg bg-theme-status-error/10 text-theme-status-error">
        {error}
      </div>
    );
  }

  if (!progress) return null;

  return (
    <div className={cn('space-y-6', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <h3 className="font-medium text-theme-text-primary">Progress & Learnings</h3>
        <Button variant="ghost" size="sm" onClick={loadProgress}>
          <RefreshCw className="w-4 h-4" />
        </Button>
      </div>

      {/* Progress Text */}
      {progress.progress_text && (
        <Card>
          <CardContent className="p-4">
            <div className="flex items-start gap-3">
              <FileText className="w-5 h-5 text-theme-text-secondary flex-shrink-0 mt-0.5" />
              <div>
                <h4 className="font-medium text-theme-text-primary mb-2">Progress Log</h4>
                <pre className="text-sm text-theme-text-secondary whitespace-pre-wrap font-mono bg-theme-bg-secondary p-3 rounded">
                  {progress.progress_text}
                </pre>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Learnings */}
      {progress.learnings && progress.learnings.length > 0 && (
        <Card>
          <CardContent className="p-4">
            <div className="flex items-start gap-3">
              <Lightbulb className="w-5 h-5 text-theme-status-warning flex-shrink-0 mt-0.5" />
              <div className="flex-1">
                <h4 className="font-medium text-theme-text-primary mb-3">Accumulated Learnings</h4>
                <div className="space-y-2">
                  {progress.learnings.map((learning, idx) => (
                    <div
                      key={idx}
                      className="flex items-start gap-2 p-2 bg-theme-bg-secondary rounded"
                    >
                      <span className="text-xs font-medium text-theme-text-secondary min-w-6">
                        {idx + 1}.
                      </span>
                      <p className="text-sm text-theme-text-primary">{learning}</p>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Recent Commits */}
      {progress.recent_commits && progress.recent_commits.length > 0 && (
        <Card>
          <CardContent className="p-4">
            <div className="flex items-start gap-3">
              <GitCommit className="w-5 h-5 text-theme-text-secondary flex-shrink-0 mt-0.5" />
              <div className="flex-1">
                <h4 className="font-medium text-theme-text-primary mb-3">Recent Commits</h4>
                <div className="space-y-2">
                  {progress.recent_commits.map((commit, idx) => (
                    <div
                      key={idx}
                      className="flex items-start gap-3 p-2 bg-theme-bg-secondary rounded"
                    >
                      <span className="font-mono text-xs text-theme-status-info">
                        {commit.sha.slice(0, 7)}
                      </span>
                      <p className="text-sm text-theme-text-primary flex-1">
                        {commit.message}
                      </p>
                      <span className="text-xs text-theme-text-secondary">
                        {new Date(commit.timestamp).toLocaleTimeString()}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Empty State */}
      {!progress.progress_text && (!progress.learnings || progress.learnings.length === 0) && (
        <div className="text-center py-8 text-theme-text-secondary">
          <BookOpen className="w-12 h-12 mx-auto mb-3 opacity-50" />
          <p>No progress or learnings recorded yet.</p>
          <p className="text-sm">Run iterations to accumulate knowledge.</p>
        </div>
      )}
    </div>
  );
};

export default RalphProgressView;
