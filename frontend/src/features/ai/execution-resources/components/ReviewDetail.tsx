import { Shield, Star, Clock, ExternalLink, GitCommit, AlertTriangle, CheckCircle, XCircle, MessageSquare } from 'lucide-react';
import type { ResourceDetailProps } from '../types';
import { DetailSection, StatCard, formatDuration, formatTimestamp } from './DetailSection';
import { OutputViewer } from './OutputViewer';

export function ReviewDetail({ resource }: ResourceDetailProps) {
  const findings = resource.findings || [];

  return (
    <div className="space-y-4">
      {/* Mode + Score */}
      <div className="grid grid-cols-3 gap-2">
        <StatCard label="Mode" value={resource.review_mode} icon={<Shield className="w-3.5 h-3.5" />} />
        <StatCard
          label="Quality Score"
          value={resource.quality_score != null ? Number(resource.quality_score).toFixed(2) : undefined}
          icon={<Star className="w-3.5 h-3.5" />}
          variant={Number(resource.quality_score) >= 0.7 ? 'success' : Number(resource.quality_score) >= 0.4 ? 'warning' : 'danger'}
        />
        <StatCard label="Duration" value={formatDuration(resource.review_duration_ms)} icon={<Clock className="w-3.5 h-3.5" />} />
      </div>

      {/* Reviewer + Revision count */}
      <div className="flex flex-wrap gap-3 text-sm">
        {resource.reviewer_agent_name && (
          <span className="text-theme-secondary">
            Reviewer: <span className="font-medium text-theme-primary">{resource.reviewer_agent_name}</span>
          </span>
        )}
        {resource.revision_count !== undefined && resource.revision_count > 0 && (
          <span className="text-theme-secondary">
            Revisions: <span className="font-medium text-theme-primary">{resource.revision_count}</span>
          </span>
        )}
      </div>

      {/* Approval / Rejection */}
      {resource.status === 'approved' && resource.approval_notes && (
        <div className="p-3 rounded-lg border border-theme bg-theme-success/5">
          <div className="flex items-center gap-1.5 text-xs text-theme-success mb-1">
            <CheckCircle className="w-3.5 h-3.5" />
            Approval Notes
          </div>
          <p className="text-sm text-theme-primary">{resource.approval_notes}</p>
        </div>
      )}

      {(resource.status === 'rejected' || resource.status === 'revision_requested') && resource.rejection_reason && (
        <div className="p-3 rounded-lg border border-theme bg-theme-error/5">
          <div className="flex items-center gap-1.5 text-xs text-theme-error mb-1">
            <XCircle className="w-3.5 h-3.5" />
            Rejection Reason
          </div>
          <p className="text-sm text-theme-primary">{resource.rejection_reason}</p>
        </div>
      )}

      {/* Source info */}
      {(resource.commit_sha || resource.repository_url || resource.pull_request_number) && (
        <div className="flex flex-wrap gap-3 text-sm text-theme-secondary">
          {resource.commit_sha && (
            <div className="flex items-center gap-1.5">
              <GitCommit className="w-3.5 h-3.5 text-theme-tertiary" />
              <span className="font-mono">{resource.commit_sha.slice(0, 8)}</span>
            </div>
          )}
          {resource.repository_url && (
            <a
              href={resource.repository_url}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 text-theme-primary hover:underline"
            >
              <ExternalLink className="w-3.5 h-3.5" />
              Repository
            </a>
          )}
          {resource.pull_request_number && (
            <span>PR #{resource.pull_request_number}</span>
          )}
        </div>
      )}

      {/* Timestamps */}
      {resource.created_at && (
        <div className="text-xs text-theme-tertiary">
          Created: {formatTimestamp(resource.created_at)}
        </div>
      )}

      {/* Findings */}
      {findings.length > 0 && (
        <DetailSection title={`Findings (${findings.length})`} icon={<AlertTriangle className="w-4 h-4" />} defaultOpen>
          <div className="space-y-2">
            {findings.map((finding, i) => {
              const severity = (finding.severity as string) || 'info';
              const severityColor = severity === 'critical' || severity === 'error' ? 'text-theme-error' :
                severity === 'warning' ? 'text-theme-warning' : 'text-theme-info';

              const category = finding.category ? String(finding.category) : null;
              const message = finding.message ? String(finding.message) : null;
              const file = finding.file ? String(finding.file) : null;
              const line = finding.line ? String(finding.line) : null;
              const suggestion = finding.suggestion ? String(finding.suggestion) : null;

              return (
                <div key={i} className="p-2.5 rounded-lg border border-theme">
                  <div className="flex items-center gap-2 mb-1">
                    <span className={`text-xs font-medium uppercase ${severityColor}`}>{severity}</span>
                    {category && (
                      <span className="text-xs text-theme-tertiary">{category}</span>
                    )}
                  </div>
                  {message && (
                    <p className="text-sm text-theme-primary">{message}</p>
                  )}
                  {file && (
                    <p className="text-xs font-mono text-theme-tertiary mt-1">
                      {file}{line ? `:${line}` : ''}
                    </p>
                  )}
                  {suggestion && (
                    <p className="text-xs text-theme-secondary mt-1 italic">{suggestion}</p>
                  )}
                </div>
              );
            })}
          </div>
        </DetailSection>
      )}

      {/* Diff analysis */}
      {resource.diff_analysis && Object.keys(resource.diff_analysis).length > 0 && (
        <DetailSection title="Diff Analysis" defaultOpen={false}>
          <OutputViewer data={resource.diff_analysis} />
        </DetailSection>
      )}

      {/* File comments */}
      {resource.file_comments && Object.keys(resource.file_comments).length > 0 && (
        <DetailSection title="File Comments" icon={<MessageSquare className="w-4 h-4" />} defaultOpen={false}>
          <OutputViewer data={resource.file_comments} />
        </DetailSection>
      )}

      {/* Code suggestions */}
      {resource.code_suggestions && Object.keys(resource.code_suggestions).length > 0 && (
        <DetailSection title="Code Suggestions" defaultOpen={false}>
          <OutputViewer data={resource.code_suggestions} />
        </DetailSection>
      )}

      {/* Completeness checks */}
      {resource.completeness_checks && Object.keys(resource.completeness_checks).length > 0 && (
        <DetailSection title="Completeness Checks" defaultOpen={false}>
          <OutputViewer data={resource.completeness_checks} />
        </DetailSection>
      )}
    </div>
  );
}
