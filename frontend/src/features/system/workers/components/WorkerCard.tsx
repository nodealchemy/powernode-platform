import React, { useState } from 'react';
import { Worker, UpdateWorkerData } from '@/features/system/workers/services/workerApi';
import { formatDate } from '@/shared/utils/formatters';
import { 
  Eye, 
  Edit, 
  Trash2, 
  MoreVertical, 
  Shield, 
  Activity, 
  Calendar,
  Key,
  Copy,
  Check
} from 'lucide-react';
import { copyToClipboard } from '@/shared/utils/clipboard';

export interface WorkerCardProps {
  worker: Worker;
  isSelected: boolean;
  onSelect: (selected: boolean) => void;
  onView: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
  isExpanded?: boolean;
  onUpdateWorker?: (workerId: string, data: UpdateWorkerData) => Promise<void>;
  onDeleteWorker?: (workerId: string) => Promise<void>;
  onCloseExpanded?: () => void;
}

export const WorkerCard: React.FC<WorkerCardProps> = ({
  worker,
  isSelected,
  onSelect,
  onView,
  onEdit,
  onDelete,
  onUpdateWorker: _onUpdateWorker,
  onDeleteWorker: _onDeleteWorker,
  onCloseExpanded: _onCloseExpanded
}) => {
  const [showActions, setShowActions] = useState(false);
  const [copied, setCopied] = useState(false);

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active': return 'bg-theme-success-background text-theme-success';
      case 'suspended': return 'bg-theme-warning-background text-theme-warning';
      case 'revoked': return 'bg-theme-error-background text-theme-error';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'active': return '✅';
      case 'suspended': return '⏸️';
      case 'revoked': return '❌';
      default: return '❓';
    }
  };

  const getWorkerTypeIcon = (accountName: string) => {
    return accountName === 'System' ? '⚙️' : '👥';
  };

  const formatMaskedToken = (token: string): string => {
    // Backend now provides pre-masked tokens, return as-is
    return token;
  };


  const formatLastSeen = (dateString: string | null) => {
    if (!dateString) return 'Never';
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 30) return `${diffDays}d ago`;
    return formatDate(dateString);
  };

  const copyTokenToClipboard = async (e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await copyToClipboard(worker.full_token_hash || '');
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (_error) {
    // Error silently ignored
  }
  };

  const isSystemWorker = worker.account_name === 'System';

  return (
    <div className={`
      relative bg-theme-surface rounded-xl border-2 transition-all duration-200 hover:shadow-lg hover:scale-[1.02] cursor-pointer h-full flex flex-col
      ${isSelected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-secondary'}
      ${isSystemWorker ? 'bg-gradient-to-br from-theme-surface to-theme-info/5 border-theme-info/30 shadow-md' : ''}
    `}>
      {/* Selection Checkbox */}
      <div className="absolute top-3 left-3 z-10">
        <input
          type="checkbox"
          checked={isSelected}
          onChange={(e) => {
            e.stopPropagation();
            onSelect(e.target.checked);
          }}
          className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
        />
      </div>

      {/* Actions Menu */}
      <div className="absolute top-3 right-3 z-10">
        <div className="relative">
          <button
            onClick={(e) => {
              e.stopPropagation();
              setShowActions(!showActions);
            }}
            className="p-2 rounded-lg bg-theme-background/80 text-theme-secondary hover:text-theme-primary transition-colors"
          >
            <MoreVertical className="w-4 h-4" />
          </button>

          {showActions && (
            <div className="absolute right-0 top-full mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-xl z-20">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onView();
                  setShowActions(false);
                }}
                className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-background transition-colors"
              >
                <Eye className="w-4 h-4" />
                View Details
              </button>
              {onEdit && (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onEdit();
                    setShowActions(false);
                  }}
                  className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-background transition-colors"
                >
                  <Edit className="w-4 h-4" />
                  Edit Worker
                </button>
              )}
              {onDelete && (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onDelete();
                    setShowActions(false);
                  }}
                  className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-error hover:bg-theme-error-background transition-colors"
                >
                  <Trash2 className="w-4 h-4" />
                  Delete Worker
                </button>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Card Content */}
      <div className="p-6 h-full flex flex-col" onClick={onView}>
        {/* Header - Fixed Height */}
        <div className="flex-shrink-0">
          {/* Worker Name & Type */}
          <div className="flex items-start justify-between pr-8 mb-3">
            <div className="min-h-[3rem] flex flex-col justify-start">
              <h3 className="font-semibold text-theme-primary text-lg line-clamp-2 leading-tight">
                {worker.name}
              </h3>
              <div className="flex items-center gap-2 mt-1">
                <span className="text-sm text-theme-secondary">
                  {getWorkerTypeIcon(worker.account_name)} {worker.account_name}
                </span>
              </div>
            </div>
          </div>

          {/* Description - Fixed Height */}
          <div className="h-10 mb-3">
            <p className="text-theme-secondary text-sm line-clamp-2 leading-tight">
              {worker.description || ' '}
            </p>
          </div>

          {/* Status */}
          <div className="flex items-center gap-2 flex-wrap mb-4">
            <span className={`px-3 py-1 rounded-full text-xs font-medium ${getStatusColor(worker.status)}`}>
              {getStatusIcon(worker.status)} {worker.status.charAt(0).toUpperCase() + worker.status.slice(1)}
            </span>
            {worker.active_recently ? (
              <span className="px-2 py-1 bg-theme-success-background text-theme-success text-xs rounded-full font-medium">
                🟢 Online
              </span>
            ) : (
              <span className="px-2 py-1 bg-theme-secondary-background text-theme-secondary text-xs rounded-full font-medium">
                ⚫ Offline
              </span>
            )}
          </div>
        </div>

        {/* Expandable Content */}
        <div className="flex-1 flex flex-col">
          {/* Roles & Permissions Preview */}
          <div className="border-t border-theme pt-4 flex-1 space-y-3">
            {/* Roles */}
            <div>
              <div className="flex items-center gap-1 text-xs text-theme-secondary mb-1">
                <Shield className="w-3 h-3" />
                <span>Roles ({worker.roles.length})</span>
              </div>
              <div className="flex flex-wrap gap-1">
                {worker.roles.slice(0, 3).map((role, index) => (
                  <span
                    key={index}
                    className="px-2 py-1 bg-theme-warning-background text-theme-warning text-xs rounded-full"
                  >
                    {role}
                  </span>
                ))}
                {worker.roles.length > 3 && (
                  <span className="px-2 py-1 bg-theme-info-background text-theme-info text-xs rounded-full">
                    +{worker.roles.length - 3} more
                  </span>
                )}
              </div>
            </div>

            {/* Key Permissions Preview */}
            <div>
              <div className="flex items-center gap-1 text-xs text-theme-secondary mb-1">
                <Key className="w-3 h-3" />
                <span>Key Permissions</span>
              </div>
              <div className="flex flex-wrap gap-1">
                {worker.permissions.slice(0, 2).map((permission, index) => (
                  <span
                    key={index}
                    className="px-2 py-1 bg-theme-surface text-theme-primary text-xs rounded-full font-mono"
                    title={permission}
                  >
                    {permission.split('.').pop()}
                  </span>
                ))}
                {worker.permissions.length > 2 && (
                  <span className="px-2 py-1 bg-theme-info-background text-theme-info text-xs rounded-full">
                    +{worker.permissions.length - 2} more
                  </span>
                )}
              </div>
            </div>
          </div>

          {/* Token & Stats - Fixed at bottom */}
          <div className="mt-4 pt-4 border-t border-theme space-y-3">
            {/* Token */}
            <div>
              <div className="flex items-center gap-1 text-xs text-theme-secondary mb-1">
                <Key className="w-3 h-3" />
                <span>Token</span>
              </div>
              <div className="flex items-center gap-2">
                <code className="flex-1 text-xs font-mono bg-theme-background px-2 py-1 rounded text-theme-primary">
                  {formatMaskedToken(worker.masked_token)}
                </code>
                <button
                  onClick={copyTokenToClipboard}
                  className="p-1 text-theme-secondary hover:text-theme-primary transition-colors"
                  title="Copy full hash"
                >
                  {copied ? <Check className="w-3 h-3 text-theme-success" /> : <Copy className="w-3 h-3" />}
                </button>
              </div>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <div className="flex items-center gap-1 text-xs text-theme-secondary">
                  <Activity className="w-3 h-3" />
                  <span>Requests</span>
                </div>
                <div className="text-sm font-medium text-theme-primary">
                  {worker.request_count.toLocaleString()}
                </div>
              </div>
              <div>
                <div className="flex items-center gap-1 text-xs text-theme-secondary">
                  <Calendar className="w-3 h-3" />
                  <span>Last Seen</span>
                </div>
                <div className="text-sm font-medium text-theme-primary">
                  {formatLastSeen(worker.last_seen_at)}
                </div>
              </div>
            </div>

            {/* Footer */}
            <div className="pt-2 border-t border-theme">
              <div className="text-xs text-theme-secondary">
                Created {formatDate(worker.created_at)}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* System Worker Badge */}
      {isSystemWorker && (
        <div className="absolute -top-2 -right-2">
          <div className="bg-theme-error text-white px-2 py-1 rounded-full text-xs font-medium shadow-lg">
            ⚙️ SYSTEM
          </div>
        </div>
      )}

      {/* Click overlay for closing actions menu */}
      {showActions && (
        <div 
          className="fixed inset-0 z-10"
          onClick={() => setShowActions(false)}
        />
      )}
    </div>
  );
};

