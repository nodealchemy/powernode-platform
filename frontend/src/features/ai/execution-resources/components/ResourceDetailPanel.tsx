import { FolderOutput, Loader2 } from 'lucide-react';
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

interface ResourceDetailPanelProps {
  resource: ExecutionResource | null;
  detailResource: ResourceDetail | null;
  detailLoading: boolean;
}

function renderDetailContent(resource: ExecutionResource, detail: ResourceDetail | null, detailLoading: boolean) {
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
}

export function ResourceDetailPanel({ resource, detailResource, detailLoading }: ResourceDetailPanelProps) {
  if (!resource) {
    return (
      <div className="flex-1 flex items-center justify-center bg-theme-bg">
        <div className="text-center text-theme-tertiary">
          <FolderOutput className="w-10 h-10 mx-auto mb-3 opacity-40" />
          <p className="text-sm">Select a resource to view details</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-6 bg-theme-bg">
      <div className="mb-6">
        <h2 className="text-lg font-semibold text-theme-primary">{resource.name}</h2>
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
      {renderDetailContent(resource, detailResource, detailLoading)}
    </div>
  );
}
