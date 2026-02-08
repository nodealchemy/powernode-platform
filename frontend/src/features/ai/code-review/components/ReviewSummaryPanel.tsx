import React from 'react';
import { BarChart3, AlertTriangle, CheckCircle, FileText, Lightbulb } from 'lucide-react';
import type { CodeReviewComment } from '../services/codeReviewApi';

interface ReviewData {
  quality_score?: number;
  status?: string;
}

interface ReviewSummaryPanelProps {
  review: ReviewData;
  comments: CodeReviewComment[];
}

export const ReviewSummaryPanel: React.FC<ReviewSummaryPanelProps> = ({ review, comments }) => {
  const qualityScore = review.quality_score ?? 0;
  const qualityPercent = Math.round(qualityScore * 100);

  const criticalCount = comments.filter(c => c.severity === 'critical').length;
  const warningCount = comments.filter(c => c.severity === 'warning').length;
  const infoCount = comments.filter(c => c.severity === 'info').length;
  const suggestionCount = comments.filter(c => c.comment_type === 'suggestion').length;
  const resolvedCount = comments.filter(c => c.resolved).length;

  // Group comments by file
  const fileMap = new Map<string, CodeReviewComment[]>();
  comments.forEach(c => {
    const existing = fileMap.get(c.file_path) || [];
    existing.push(c);
    fileMap.set(c.file_path, existing);
  });

  const scoreColor = qualityPercent >= 80 ? 'text-theme-success' : qualityPercent >= 50 ? 'text-theme-warning' : 'text-theme-danger';
  const scoreBg = qualityPercent >= 80 ? 'bg-theme-success/10' : qualityPercent >= 50 ? 'bg-theme-warning/10' : 'bg-theme-error/10';

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 space-y-4">
      <div className="flex items-center gap-2">
        <BarChart3 className="h-4 w-4 text-theme-primary" />
        <h4 className="text-sm font-semibold text-theme-primary">Review Summary</h4>
      </div>

      {/* Quality Score */}
      <div className="flex items-center gap-4">
        <div className={`h-16 w-16 rounded-full flex items-center justify-center ${scoreBg}`}>
          <span className={`text-xl font-bold ${scoreColor}`}>{qualityPercent}</span>
        </div>
        <div>
          <p className="text-sm font-medium text-theme-primary">Quality Score</p>
          <p className="text-xs text-theme-secondary">{comments.length} issues found, {resolvedCount} resolved</p>
        </div>
      </div>

      {/* Issue Breakdown */}
      <div className="grid grid-cols-3 gap-3">
        <div className="text-center p-2 rounded-md bg-theme-error/5 border border-theme-danger/20">
          <div className="text-lg font-bold text-theme-danger">{criticalCount}</div>
          <div className="text-xs text-theme-secondary">Critical</div>
        </div>
        <div className="text-center p-2 rounded-md bg-theme-warning/5 border border-theme-warning/20">
          <div className="text-lg font-bold text-theme-warning">{warningCount}</div>
          <div className="text-xs text-theme-secondary">Warning</div>
        </div>
        <div className="text-center p-2 rounded-md bg-theme-info/5 border border-theme-info/20">
          <div className="text-lg font-bold text-theme-info">{infoCount}</div>
          <div className="text-xs text-theme-secondary">Info</div>
        </div>
      </div>

      {/* Suggestions */}
      {suggestionCount > 0 && (
        <div className="flex items-center gap-2 text-xs text-theme-secondary">
          <Lightbulb className="h-3 w-3 text-theme-warning" />
          {suggestionCount} suggestion{suggestionCount !== 1 ? 's' : ''} available
        </div>
      )}

      {/* File Breakdown */}
      {fileMap.size > 0 && (
        <div>
          <h5 className="text-xs font-medium text-theme-secondary mb-2">Files Reviewed</h5>
          <div className="space-y-1">
            {Array.from(fileMap.entries()).map(([filePath, fileComments]) => (
              <div key={filePath} className="flex items-center justify-between text-xs">
                <div className="flex items-center gap-1.5 truncate">
                  <FileText className="h-3 w-3 text-theme-secondary flex-shrink-0" />
                  <span className="truncate text-theme-primary font-mono">{filePath}</span>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0 ml-2">
                  {fileComments.some(c => c.severity === 'critical') && (
                    <AlertTriangle className="h-3 w-3 text-theme-danger" />
                  )}
                  <span className="text-theme-secondary">{fileComments.length}</span>
                  {fileComments.every(c => c.resolved) && (
                    <CheckCircle className="h-3 w-3 text-theme-success" />
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
