import React from 'react';
import { useNavigate } from 'react-router-dom';
import { Play, Clock, Copy, Trash2, MoreVertical, FileCode } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { DevopsPipeline } from '@/types/devops-pipelines';

interface PipelineListProps {
  pipelines: DevopsPipeline[];
  loading: boolean;
  onTrigger: (id: string) => void;
  onDuplicate: (id: string) => void;
  onDelete: (id: string) => void;
  onExportYaml: (id: string) => void;
}

const StatusBadge: React.FC<{ isActive: boolean }> = ({ isActive }) => (
  <span
    className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
      isActive
        ? 'bg-theme-success/10 text-theme-success'
        : 'bg-theme-secondary/10 text-theme-secondary'
    }`}
  >
    {isActive ? 'Active' : 'Inactive'}
  </span>
);

const formatTimeAgo = (dateString: string | null): string => {
  if (!dateString) return 'Never';
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  return `${diffDays}d ago`;
};

const PipelineCard: React.FC<{
  pipeline: DevopsPipeline;
  onTrigger: () => void;
  onDuplicate: () => void;
  onDelete: () => void;
  onExportYaml: () => void;
  onClick: () => void;
}> = ({ pipeline, onTrigger, onDuplicate, onDelete, onExportYaml, onClick }) => {
  const [showMenu, setShowMenu] = React.useState(false);

  return (
    <div className="bg-theme-surface rounded-lg border border-theme hover:border-theme-primary transition-colors">
      <button
        onClick={onClick}
        className="w-full p-4 text-left"
      >
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-primary/10 rounded-lg">
              <Play className="w-5 h-5 text-theme-primary" />
            </div>
            <div>
              <h3 className="font-medium text-theme-primary">{pipeline.name}</h3>
              <p className="text-sm text-theme-tertiary">{pipeline.slug}</p>
            </div>
          </div>
          <StatusBadge isActive={pipeline.is_active} />
        </div>

        {pipeline.description && (
          <p className="mt-3 text-sm text-theme-secondary line-clamp-2">
            {pipeline.description}
          </p>
        )}

        <div className="mt-4 flex items-center gap-4 text-xs text-theme-tertiary">
          <span className="flex items-center gap-1">
            <Play className="w-3 h-3" />
            {pipeline.run_count} runs
          </span>
          <span className="flex items-center gap-1">
            <Clock className="w-3 h-3" />
            Last run: {formatTimeAgo(pipeline.last_run?.started_at || null)}
          </span>
          <span>{pipeline.step_count} steps</span>
        </div>
      </button>

      <div className="px-4 pb-4 flex items-center justify-between border-t border-theme pt-3 mt-3">
        <div className="flex items-center gap-2">
          <Button
            onClick={(e) => {
              e.stopPropagation();
              onTrigger();
            }}
            variant="primary"
            size="sm"
            disabled={!pipeline.is_active}
          >
            <Play className="w-4 h-4 mr-1" />
            Trigger
          </Button>
        </div>

        <div className="relative">
          <Button
            onClick={(e) => {
              e.stopPropagation();
              setShowMenu(!showMenu);
            }}
            variant="ghost"
            size="sm"
          >
            <MoreVertical className="w-4 h-4" />
          </Button>

          {showMenu && (
            <>
              <div
                className="fixed inset-0 z-10"
                onClick={() => setShowMenu(false)}
              />
              <div className="absolute right-0 top-full mt-1 w-48 bg-theme-surface rounded-lg shadow-lg border border-theme z-20">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onExportYaml();
                    setShowMenu(false);
                  }}
                  className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                >
                  <FileCode className="w-4 h-4" />
                  Export YAML
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onDuplicate();
                    setShowMenu(false);
                  }}
                  className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                >
                  <Copy className="w-4 h-4" />
                  Duplicate
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onDelete();
                    setShowMenu(false);
                  }}
                  className="w-full px-4 py-2 text-left text-sm text-theme-error hover:bg-theme-error/10 flex items-center gap-2"
                >
                  <Trash2 className="w-4 h-4" />
                  Delete
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export const PipelineList: React.FC<PipelineListProps> = ({
  pipelines,
  loading,
  onTrigger,
  onDuplicate,
  onDelete,
  onExportYaml,
}) => {
  const navigate = useNavigate();

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (pipelines.length === 0) {
    return (
      <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
        <Play className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">
          No Pipelines Yet
        </h3>
        <p className="text-theme-secondary mb-4">
          Create your first AI-powered DevOps pipeline to get started.
        </p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {pipelines.map((pipeline) => (
        <PipelineCard
          key={pipeline.id}
          pipeline={pipeline}
          onTrigger={() => onTrigger(pipeline.id)}
          onDuplicate={() => onDuplicate(pipeline.id)}
          onDelete={() => onDelete(pipeline.id)}
          onExportYaml={() => onExportYaml(pipeline.id)}
          onClick={() => navigate(`/app/devops/pipelines/${pipeline.id}`)}
        />
      ))}
    </div>
  );
};

export default PipelineList;
