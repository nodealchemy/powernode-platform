

import { X } from 'lucide-react';
import type { ExecutionResource } from '../types';
import { ArtifactContentViewer } from './ArtifactContentViewer';
import { GitResourceDetail } from './GitResourceDetail';
import { SharedMemoryDetail } from './SharedMemoryDetail';
import { RunnerJobDetail } from './RunnerJobDetail';
import { OutputViewer } from './OutputViewer';

interface ResourceDetailDrawerProps {
  resource: ExecutionResource | null;
  onClose: () => void;
}

export function ResourceDetailDrawer({ resource, onClose }: ResourceDetailDrawerProps) {
  if (!resource) return null;

  const renderDetail = () => {
    switch (resource.resource_type) {
      case 'artifact':
        return <ArtifactContentViewer resource={resource} />;
      case 'git_branch':
      case 'git_merge':
        return <GitResourceDetail resource={resource} />;
      case 'shared_memory':
        return <SharedMemoryDetail resource={resource} />;
      case 'runner_job':
        return <RunnerJobDetail resource={resource} />;
      case 'execution_output':
        return <OutputViewer data={resource.metadata} />;
      case 'trajectory':
      case 'review':
      default:
        return <OutputViewer data={resource} />;
    }
  };

  return (
    <div className="fixed inset-y-0 right-0 w-full max-w-lg z-50 flex">
      <div className="fixed inset-0 bg-black/30" onClick={onClose} />
      <div className="relative ml-auto w-full max-w-lg bg-theme-bg-primary border-l border-theme-border shadow-xl flex flex-col overflow-hidden">
        <div className="flex items-center justify-between p-4 border-b border-theme-border">
          <div>
            <h2 className="text-lg font-semibold text-theme-text-primary">{resource.name}</h2>
            <p className="text-sm text-theme-text-secondary capitalize">
              {resource.resource_type.replace('_', ' ')} &middot; {resource.status}
            </p>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-lg hover:bg-theme-bg-secondary transition-colors text-theme-text-secondary"
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
