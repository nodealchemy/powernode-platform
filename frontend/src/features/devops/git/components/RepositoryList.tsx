import React, { useState } from 'react';
import {
  GitBranch,
  Star,
  GitFork,
  Lock,
  Globe,
  Webhook,
  Play,
  MoreVertical,
  ExternalLink,
  Trash2,
  RefreshCw,
} from 'lucide-react';
import { GitRepository } from '../types';
import { useNotification } from '@/shared/hooks/useNotification';

interface RepositoryListProps {
  repositories: GitRepository[];
  loading?: boolean;
  onConfigureWebhook: (id: string) => Promise<void>;
  onRemoveWebhook: (id: string) => Promise<void>;
  onSyncPipelines: (id: string) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
  onSelectRepository?: (repo: GitRepository) => void;
}

export const RepositoryList: React.FC<RepositoryListProps> = ({
  repositories,
  loading,
  onConfigureWebhook,
  onRemoveWebhook,
  onSyncPipelines,
  onDelete,
  onSelectRepository,
}) => {
  const { showNotification } = useNotification();
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState<string | null>(null);

  const handleAction = async (
    id: string,
    action: () => Promise<void>,
    successMessage: string
  ) => {
    try {
      setActionLoading(id);
      setMenuOpen(null);
      await action();
      showNotification({ type: 'success', message: successMessage });
    } catch {
      showNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Action failed',
      });
    } finally {
      setActionLoading(null);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-48">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
      </div>
    );
  }

  if (repositories.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface rounded-lg border border-theme">
        <GitBranch className="w-12 h-12 mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">
          No Repositories Found
        </h3>
        <p className="text-theme-secondary">
          Sync your repositories from a Git provider to get started.
        </p>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="border-b border-theme bg-theme-hover/50">
              <th className="text-left px-4 py-3 text-sm font-medium text-theme-secondary">
                Repository
              </th>
              <th className="text-left px-4 py-3 text-sm font-medium text-theme-secondary">
                Provider
              </th>
              <th className="text-left px-4 py-3 text-sm font-medium text-theme-secondary">
                Stats
              </th>
              <th className="text-left px-4 py-3 text-sm font-medium text-theme-secondary">
                Webhook
              </th>
              <th className="text-right px-4 py-3 text-sm font-medium text-theme-secondary">
                Actions
              </th>
            </tr>
          </thead>
          <tbody>
            {repositories.map((repo) => (
              <tr
                key={repo.id}
                className="border-b border-theme last:border-0 hover:bg-theme-hover/50 cursor-pointer"
                onClick={() => onSelectRepository?.(repo)}
              >
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    {repo.is_private ? (
                      <Lock className="w-4 h-4 text-theme-warning" />
                    ) : (
                      <Globe className="w-4 h-4 text-theme-success" />
                    )}
                    <div>
                      <div className="font-medium text-theme-primary">
                        {repo.name}
                      </div>
                      <div className="text-sm text-theme-secondary">
                        {repo.owner}
                      </div>
                    </div>
                    {repo.is_fork && (
                      <GitFork className="w-3 h-3 text-theme-secondary" />
                    )}
                  </div>
                </td>
                <td className="px-4 py-3">
                  <span className="px-2 py-1 text-xs rounded-full bg-theme-primary/10 text-theme-primary capitalize">
                    {repo.provider_type}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-4 text-sm text-theme-secondary">
                    <span className="flex items-center gap-1">
                      <Star className="w-3 h-3" />
                      {repo.stars_count}
                    </span>
                    <span className="flex items-center gap-1">
                      <GitFork className="w-3 h-3" />
                      {repo.forks_count}
                    </span>
                  </div>
                </td>
                <td className="px-4 py-3">
                  {repo.webhook_configured ? (
                    <span className="flex items-center gap-1 text-sm text-theme-success">
                      <Webhook className="w-4 h-4" />
                      Active
                    </span>
                  ) : (
                    <span className="flex items-center gap-1 text-sm text-theme-secondary">
                      <Webhook className="w-4 h-4" />
                      Not configured
                    </span>
                  )}
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center justify-end gap-2">
                    {repo.web_url && (
                      <a
                        href={repo.web_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="p-1 rounded hover:bg-theme-hover text-theme-secondary"
                        onClick={(e) => e.stopPropagation()}
                      >
                        <ExternalLink className="w-4 h-4" />
                      </a>
                    )}

                    <div className="relative">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          setMenuOpen(menuOpen === repo.id ? null : repo.id);
                        }}
                        className="p-1 rounded hover:bg-theme-hover text-theme-secondary"
                        disabled={actionLoading === repo.id}
                      >
                        {actionLoading === repo.id ? (
                          <RefreshCw className="w-4 h-4 animate-spin" />
                        ) : (
                          <MoreVertical className="w-4 h-4" />
                        )}
                      </button>

                      {menuOpen === repo.id && (
                        <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              handleAction(
                                repo.id,
                                () => onSyncPipelines(repo.id),
                                'Pipelines synced'
                              );
                            }}
                            className="w-full px-3 py-2 text-left text-sm text-theme-primary hover:bg-theme-hover flex items-center gap-2"
                          >
                            <Play className="w-4 h-4" />
                            Sync Pipelines
                          </button>

                          {repo.webhook_configured ? (
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                handleAction(
                                  repo.id,
                                  () => onRemoveWebhook(repo.id),
                                  'Webhook removed'
                                );
                              }}
                              className="w-full px-3 py-2 text-left text-sm text-theme-primary hover:bg-theme-hover flex items-center gap-2"
                            >
                              <Webhook className="w-4 h-4" />
                              Remove Webhook
                            </button>
                          ) : (
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                handleAction(
                                  repo.id,
                                  () => onConfigureWebhook(repo.id),
                                  'Webhook configured'
                                );
                              }}
                              className="w-full px-3 py-2 text-left text-sm text-theme-primary hover:bg-theme-hover flex items-center gap-2"
                            >
                              <Webhook className="w-4 h-4" />
                              Configure Webhook
                            </button>
                          )}

                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              handleAction(
                                repo.id,
                                () => onDelete(repo.id),
                                'Repository removed'
                              );
                            }}
                            className="w-full px-3 py-2 text-left text-sm text-theme-error hover:bg-theme-hover flex items-center gap-2"
                          >
                            <Trash2 className="w-4 h-4" />
                            Remove
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};

export default RepositoryList;
