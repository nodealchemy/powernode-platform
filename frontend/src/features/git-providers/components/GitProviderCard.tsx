import React from 'react';
import {
  GitBranch,
  Plus,
  CheckCircle,
  Settings,
  Pencil,
  Trash2,
  MoreVertical,
} from 'lucide-react';
import { AvailableProvider } from '../types';

interface GitProviderCardProps {
  provider: AvailableProvider;
  onAddCredential: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
  canManage?: boolean;
}

const providerIcons: Record<string, string> = {
  github: 'https://cdn.simpleicons.org/github',
  gitlab: 'https://cdn.simpleicons.org/gitlab',
  gitea: 'https://cdn.simpleicons.org/gitea',
};

const providerColors: Record<string, string> = {
  github: 'bg-theme-background',
  gitlab: 'bg-theme-warning',
  gitea: 'bg-theme-success',
};

export const GitProviderCard: React.FC<GitProviderCardProps> = ({
  provider,
  onAddCredential,
  onEdit,
  onDelete,
  canManage = false,
}) => {
  const [showMenu, setShowMenu] = React.useState(false);
  const iconUrl = providerIcons[provider.provider_type];
  const bgColor = providerColors[provider.provider_type] || 'bg-theme-primary';

  return (
    <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden hover:shadow-md transition-shadow">
      {/* Header */}
      <div className={`${bgColor} p-4`}>
        <div className="flex items-center gap-3">
          {iconUrl ? (
            <img
              src={iconUrl}
              alt={provider.name}
              className="w-8 h-8 rounded bg-white p-1"
            />
          ) : (
            <div className="w-8 h-8 rounded bg-white/20 flex items-center justify-center">
              <GitBranch className="w-5 h-5 text-white" />
            </div>
          )}
          <div className="flex-1 min-w-0">
            <h3 className="font-semibold text-white truncate">{provider.name}</h3>
            <p className="text-sm text-white/80 capitalize">
              {provider.provider_type}
            </p>
          </div>
          <div className="flex items-center gap-1">
            {provider.configured && (
              <CheckCircle className="w-5 h-5 text-white" />
            )}
            {canManage && (onEdit || onDelete) && (
              <div className="relative">
                <button
                  onClick={() => setShowMenu(!showMenu)}
                  className="p-1 rounded-full hover:bg-white/20 text-white"
                >
                  <MoreVertical className="w-4 h-4" />
                </button>
                {showMenu && (
                  <>
                    <div
                      className="fixed inset-0 z-10"
                      onClick={() => setShowMenu(false)}
                    />
                    <div className="absolute right-0 top-full mt-1 bg-theme-surface border border-theme rounded-lg shadow-lg z-20 py-1 min-w-[120px]">
                      {onEdit && (
                        <button
                          onClick={() => {
                            setShowMenu(false);
                            onEdit();
                          }}
                          className="w-full px-3 py-2 text-left text-sm text-theme-primary hover:bg-theme-hover flex items-center gap-2"
                        >
                          <Pencil className="w-4 h-4" />
                          Edit
                        </button>
                      )}
                      {onDelete && (
                        <button
                          onClick={() => {
                            setShowMenu(false);
                            onDelete();
                          }}
                          className="w-full px-3 py-2 text-left text-sm text-theme-error hover:bg-theme-hover flex items-center gap-2"
                        >
                          <Trash2 className="w-4 h-4" />
                          Delete
                        </button>
                      )}
                    </div>
                  </>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Body */}
      <div className="p-4">
        {provider.description && (
          <p className="text-sm text-theme-secondary mb-4">
            {provider.description}
          </p>
        )}

        {/* Capabilities */}
        <div className="flex flex-wrap gap-2 mb-4">
          {provider.supports_oauth && (
            <span className="px-2 py-1 text-xs rounded-full bg-theme-primary/10 text-theme-primary">
              OAuth
            </span>
          )}
          {provider.supports_pat && (
            <span className="px-2 py-1 text-xs rounded-full bg-theme-success/10 text-theme-success">
              PAT
            </span>
          )}
          {provider.supports_ci_cd && (
            <span className="px-2 py-1 text-xs rounded-full bg-theme-warning/10 text-theme-warning">
              CI/CD
            </span>
          )}
        </div>

        {/* Actions */}
        <div className="flex gap-2">
          {provider.configured ? (
            <>
              <button
                onClick={onAddCredential}
                className="flex-1 btn-theme btn-theme-outline btn-theme-sm flex items-center justify-center gap-2"
                disabled={!canManage}
              >
                <Settings className="w-4 h-4" />
                Manage
              </button>
            </>
          ) : (
            <button
              onClick={onAddCredential}
              className="flex-1 btn-theme btn-theme-primary btn-theme-sm flex items-center justify-center gap-2"
              disabled={!canManage}
            >
              <Plus className="w-4 h-4" />
              Connect
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

export default GitProviderCard;
