import React, { useState } from 'react';
import { ChevronDown, Clock, Play, CheckCircle, XCircle, Loader2, MinusCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { GitPipelineJob } from '../types';

interface JobsListProps {
  jobs: GitPipelineJob[];
  selectedJobId?: string;
  onSelectJob: (job: GitPipelineJob) => void;
  loading?: boolean;
}

const StatusIcon: React.FC<{ status: string; conclusion?: string }> = ({ status, conclusion }) => {
  if (status === 'completed') {
    switch (conclusion) {
      case 'success':
        return <CheckCircle className="w-5 h-5 text-theme-success" />;
      case 'failure':
        return <XCircle className="w-5 h-5 text-theme-error" />;
      case 'cancelled':
        return <MinusCircle className="w-5 h-5 text-theme-warning" />;
      case 'skipped':
        return <MinusCircle className="w-5 h-5 text-theme-secondary" />;
      default:
        return <MinusCircle className="w-5 h-5 text-theme-secondary" />;
    }
  }
  switch (status) {
    case 'running':
      return <Loader2 className="w-5 h-5 text-theme-info animate-spin" />;
    case 'pending':
    case 'queued':
      return <Play className="w-5 h-5 text-theme-warning" />;
    default:
      return <Play className="w-5 h-5 text-theme-secondary" />;
  }
};

const formatDuration = (seconds: number): string => {
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m ${Math.round(seconds % 60)}s`;
  return `${Math.round(seconds / 3600)}h ${Math.round((seconds % 3600) / 60)}m`;
};

const JobCard: React.FC<{
  job: GitPipelineJob;
  isSelected: boolean;
  isExpanded: boolean;
  onToggleExpand: () => void;
  onSelect: () => void;
}> = ({ job, isSelected, isExpanded, onToggleExpand, onSelect }) => {
  return (
    <div
      className={`border rounded-lg transition-colors ${
        isSelected
          ? 'border-theme-primary bg-theme-primary/5'
          : 'border-theme hover:border-theme-secondary'
      }`}
    >
      <button
        className="w-full flex items-center justify-between p-3 text-left"
        onClick={onToggleExpand}
      >
        <div className="flex items-center gap-3">
          <StatusIcon status={job.status} conclusion={job.conclusion} />
          <div>
            <p className="font-medium text-theme-primary">{job.name}</p>
            <div className="flex items-center gap-2 text-xs text-theme-tertiary mt-0.5">
              {job.runner_name && <span>Runner: {job.runner_name}</span>}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-3">
          {job.duration_seconds && (
            <div className="flex items-center gap-1 text-xs text-theme-tertiary">
              <Clock className="w-3.5 h-3.5" />
              {formatDuration(job.duration_seconds)}
            </div>
          )}
          <ChevronDown
            className={`w-4 h-4 text-theme-tertiary transition-transform ${
              isExpanded ? 'rotate-180' : ''
            }`}
          />
        </div>
      </button>

      {isExpanded && (
        <div className="px-3 pb-3 border-t border-theme pt-3">
          {/* Job Details */}
          <div className="grid grid-cols-2 gap-2 text-xs mb-3">
            <div>
              <span className="text-theme-tertiary">Status:</span>{' '}
              <span className="text-theme-primary capitalize">{job.status}</span>
            </div>
            {job.conclusion && (
              <div>
                <span className="text-theme-tertiary">Conclusion:</span>{' '}
                <span className="text-theme-primary capitalize">{job.conclusion}</span>
              </div>
            )}
            {job.started_at && (
              <div>
                <span className="text-theme-tertiary">Started:</span>{' '}
                <span className="text-theme-primary">
                  {new Date(job.started_at).toLocaleString()}
                </span>
              </div>
            )}
            {job.completed_at && (
              <div>
                <span className="text-theme-tertiary">Completed:</span>{' '}
                <span className="text-theme-primary">
                  {new Date(job.completed_at).toLocaleString()}
                </span>
              </div>
            )}
          </div>

          {/* Steps Progress */}
          {job.total_steps && job.total_steps > 0 && (
            <div className="mb-3">
              <p className="text-xs text-theme-tertiary mb-2">
                Steps: {job.completed_steps || 0} / {job.total_steps}
              </p>
              <div className="w-full bg-theme-secondary/20 rounded-full h-2">
                <div
                  className="bg-theme-success h-2 rounded-full transition-all"
                  style={{ width: `${((job.completed_steps || 0) / job.total_steps) * 100}%` }}
                />
              </div>
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center gap-2">
            <Button onClick={onSelect} variant="primary" size="sm">
              View Logs
            </Button>
          </div>
        </div>
      )}
    </div>
  );
};

export const JobsList: React.FC<JobsListProps> = ({
  jobs,
  selectedJobId,
  onSelectJob,
  loading = false,
}) => {
  const [expandedJobId, setExpandedJobId] = useState<string | null>(null);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <LoadingSpinner size="md" />
        <span className="ml-3 text-theme-secondary">Loading jobs...</span>
      </div>
    );
  }

  if (jobs.length === 0) {
    return (
      <div className="text-center py-8 text-theme-secondary">
        <Play className="w-8 h-8 mx-auto mb-2 opacity-50" />
        <p>No jobs found</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {jobs.map((job) => (
        <JobCard
          key={job.id}
          job={job}
          isSelected={job.id === selectedJobId}
          isExpanded={job.id === expandedJobId}
          onToggleExpand={() =>
            setExpandedJobId((prev) => (prev === job.id ? null : job.id))
          }
          onSelect={() => onSelectJob(job)}
        />
      ))}
    </div>
  );
};

export default JobsList;
