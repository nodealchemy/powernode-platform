import { X, Loader2 } from 'lucide-react';
import type { ExecutionResource, ResourceDetail } from '../types';
import { ArtifactContentViewer } from './ArtifactContentViewer';
import { GitResourceDetail } from './GitResourceDetail';
import { SharedMemoryDetail } from './SharedMemoryDetail';
import { RunnerJobDetail } from './RunnerJobDetail';
import { ExecutionOutputDetail } from './ExecutionOutputDetail';
import { TrajectoryDetail } from './TrajectoryDetail';
import { ReviewDetail } from './ReviewDetail';
import { OutputViewer } from './OutputViewer';
import { StatusBadge, formatTimestamp } from './DetailSection';

interface ResourceDetailDrawerProps {
  resource: ExecutionResource | null;
  detailResource: ResourceDetail | null;
  detailLoading: boolean;
  onClose: () => void;
}

export function ResourceDetailDrawer({ resource, detailResource, detailLoading, onClose }: ResourceDetailDrawerProps) {
  if (!resource) return null;

  const detail = detailResource;

  const renderDetail = () => {
    if (detailLoading) {
      return (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-6 h-6 animate-spin text-theme-tertiary" />
        </div>
      );
    }

    if (!detail) {
      return <OutputViewer data={resource} />;
    }

    switch (resource.resource_type) {
      case 'artifact':
        return <ArtifactContentViewer resource={detail} />;
      case 'git_branch':
      case 'git_merge':
        return <GitResourceDetail resource={detail} />;
      case 'shared_memory':
        return <SharedMemoryDetail resource={detail} />;
      case 'runner_job':
        return <RunnerJobDetail resource={detail} />;
      case 'execution_output':
        return <ExecutionOutputDetail resource={detail} />;
      case 'trajectory':
        return <TrajectoryDetail resource={detail} />;
      case 'review':
        return <ReviewDetail resource={detail} />;
      default:
        return <OutputViewer data={detail} />;
    }
  };

  return (
    <div className="fixed inset-y-0 right-0 w-full max-w-lg z-50 flex">
      <div className="fixed inset-0 bg-black/30" onClick={onClose} />
      <div className="relative ml-auto w-full max-w-lg bg-theme-surface border-l border-theme shadow-xl flex flex-col overflow-hidden">
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <div className="min-w-0 flex-1">
            <h2 className="text-lg font-semibold text-theme-primary truncate">{resource.name}</h2>
            <div className="flex items-center gap-2 mt-1">
              <span className="text-sm text-theme-secondary capitalize">
                {resource.resource_type.replace(/_/g, ' ')}
              </span>
              <StatusBadge status={resource.status} />
            </div>
            {resource.created_at && (
              <p className="text-xs text-theme-tertiary mt-1">{formatTimestamp(resource.created_at)}</p>
            )}
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg hover:bg-theme-surface-hover transition-colors text-theme-secondary"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto p-4">
          {renderDetail()}
        </div>
      </div>
    </div>
  );
}
