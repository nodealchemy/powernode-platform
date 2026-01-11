
import { Worker, UpdateWorkerData } from '@/features/system/workers/services/workerApi';
import { WorkerDetailsPanel } from './WorkerDetailsPanel';
import { ChevronUp, ChevronDown, ChevronLeft, ChevronRight, Eye, Copy, Check } from 'lucide-react';
import { useState } from 'react';
import { copyToClipboard } from '@/shared/utils/clipboard';

export interface WorkerTableProps {
  workers: Worker[];
  selectedWorkers: Set<string>;
  onWorkerSelect: (workerId: string, selected: boolean) => void;
  onWorkerView: (worker: Worker) => void;
  sortBy: string;
  sortOrder: 'asc' | 'desc';
  onSort: (sortBy: string, sortOrder: 'asc' | 'desc') => void;
  pagination: {
    page: number;
    pageSize: number;
    total: number;
  };
  onPaginationChange: (pagination: { page?: number; pageSize?: number }) => void;
  expandedWorker: Worker | null;
  isExpanded: boolean;
  onUpdateWorker: (workerId: string, data: UpdateWorkerData) => Promise<void>;
  onDeleteWorker: (workerId: string) => Promise<void>;
  onCloseExpanded: () => void;
}

export const WorkerTable: React.FC<WorkerTableProps> = ({
  workers,
  selectedWorkers,
  onWorkerSelect,
  onWorkerView,
  sortBy,
  sortOrder,
  onSort,
  pagination,
  onPaginationChange,
  expandedWorker,
  isExpanded,
  onUpdateWorker,
  onDeleteWorker,
  onCloseExpanded
}) => {
  const [copiedTokens, setCopiedTokens] = useState<Set<string>>(new Set());

  // Calculate pagination
  const totalPages = Math.ceil(workers.length / pagination.pageSize);
  const startIndex = (pagination.page - 1) * pagination.pageSize;
  const endIndex = Math.min(startIndex + pagination.pageSize, workers.length);
  const paginatedWorkers = workers.slice(startIndex, endIndex);

  const handleSort = (column: string) => {
    const newSortOrder = sortBy === column && sortOrder === 'asc' ? 'desc' : 'asc';
    onSort(column, newSortOrder);
  };

  const handleSelectAll = (selected: boolean) => {
    paginatedWorkers.forEach(worker => {
      onWorkerSelect(worker.id, selected);
    });
  };

  const goToPage = (page: number) => {
    onPaginationChange({ page: Math.max(1, Math.min(page, totalPages)) });
  };

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

  const formatMaskedToken = (token: string): string => {
    // Backend now provides pre-masked tokens, return as-is
    return token;
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    });
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

  const copyTokenToClipboard = async (workerId: string, token: string, e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await copyToClipboard(token);
      setCopiedTokens(prev => new Set(prev).add(workerId));
      setTimeout(() => {
        setCopiedTokens(prev => {
          const newSet = new Set(prev);
          newSet.delete(workerId);
          return newSet;
        });
      }, 2000);
    } catch (error) {
    }
  };

  const SortButton: React.FC<{ column: string; children: React.ReactNode }> = ({ column, children }) => (
    <button
      onClick={() => handleSort(column)}
      className="flex items-center gap-1 text-left hover:text-theme-interactive-primary transition-colors"
    >
      {children}
      {sortBy === column && (
        sortOrder === 'asc' ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />
      )}
    </button>
  );

  const allSelected = paginatedWorkers.length > 0 && paginatedWorkers.every(worker => selectedWorkers.has(worker.id));
  const someSelected = paginatedWorkers.some(worker => selectedWorkers.has(worker.id));

  const pageSizeOptions = [10, 25, 50, 100];

  return (
    <div className="space-y-4">
      {/* Worker Table */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-theme-background border-b border-theme">
              <tr>
            <th className="px-4 py-3 text-left w-12">
              <input
                type="checkbox"
                checked={allSelected}
                ref={(el) => {
                  if (el) el.indeterminate = someSelected && !allSelected;
                }}
                onChange={(e) => handleSelectAll(e.target.checked)}
                className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
              />
            </th>
                <th className="px-4 py-3 text-left">
                  <SortButton column="name">
                    <span className="text-sm font-medium text-theme-primary">Worker</span>
                  </SortButton>
                </th>
                <th className="px-4 py-3 text-left">
                  <span className="text-sm font-medium text-theme-primary">Status</span>
                </th>
                <th className="px-4 py-3 text-left">
                  <span className="text-sm font-medium text-theme-primary">Type</span>
                </th>
                <th className="px-4 py-3 text-left">
                  <span className="text-sm font-medium text-theme-primary">Roles</span>
                </th>
                <th className="px-4 py-3 text-left">
                  <span className="text-sm font-medium text-theme-primary">Token Hash</span>
                </th>
                <th className="px-4 py-3 text-left">
                  <SortButton column="request_count">
                    <span className="text-sm font-medium text-theme-primary">Requests</span>
                  </SortButton>
                </th>
                <th className="px-4 py-3 text-left">
                  <SortButton column="last_seen_at">
                    <span className="text-sm font-medium text-theme-primary">Last Seen</span>
                  </SortButton>
                </th>
                <th className="px-4 py-3 text-left">
                  <span className="text-sm font-medium text-theme-primary">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {paginatedWorkers.map((worker) => {
                const isSystemWorker = worker.account_name === 'System';
                return (
                <tr 
                  key={worker.id}
                  className={`hover:bg-theme-background/50 transition-colors ${
                    selectedWorkers.has(worker.id) ? 'bg-theme-interactive-primary/5' : ''
                  } ${
                    isSystemWorker ? 'bg-gradient-to-r from-theme-info/5 to-transparent border-l-2 border-theme-info/30' : ''
                  }`}
                >
                
                  {/* Checkbox */}
                  <td className="px-4 py-3">
                    <input
                      type="checkbox"
                      checked={selectedWorkers.has(worker.id)}
                      onChange={(e) => onWorkerSelect(worker.id, e.target.checked)}
                      className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                    />
                  </td>

                  {/* Worker Name & Description */}
                  <td className="px-4 py-3">
                    <div className="space-y-1">
                      <div className="font-medium text-theme-primary">{worker.name}</div>
                      {worker.description && (
                        <div className="text-sm text-theme-secondary line-clamp-1">{worker.description}</div>
                      )}
                    </div>
                  </td>

                  {/* Status */}
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className={`px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(worker.status)}`}>
                        {getStatusIcon(worker.status)} {worker.status}
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
                  </td>

                  {/* Type */}
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1 text-sm text-theme-secondary">
                      <span>{worker.account_name === 'System' ? '⚙️' : '👥'}</span>
                      <span>{worker.account_name}</span>
                    </div>
                  </td>

                  {/* Roles */}
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap gap-1 max-w-48">
                      {worker.roles.slice(0, 2).map((role, index) => (
                        <span
                          key={index}
                          className="px-2 py-1 bg-theme-warning-background text-theme-warning text-xs rounded-full"
                        >
                          {role}
                        </span>
                      ))}
                      {worker.roles.length > 2 && (
                        <span className="px-2 py-1 bg-theme-info-background text-theme-info text-xs rounded-full">
                          +{worker.roles.length - 2}
                        </span>
                      )}
                    </div>
                  </td>

                  {/* Token Hash */}
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2 max-w-40">
                      <code className="text-xs font-mono text-theme-primary bg-theme-background px-2 py-1 rounded flex-1 truncate">
                        {formatMaskedToken(worker.masked_token)}
                      </code>
                      <button
                        onClick={(e) => copyTokenToClipboard(worker.id, worker.full_token_hash || '', e)}
                        className="p-1 text-theme-secondary hover:text-theme-primary transition-colors"
                        title="Copy full hash"
                      >
                        {copiedTokens.has(worker.id) ? 
                          <Check className="w-3 h-3 text-theme-success" /> : 
                          <Copy className="w-3 h-3" />
                        }
                      </button>
                    </div>
                  </td>

                  {/* Requests */}
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-primary font-medium">
                      {worker.request_count.toLocaleString()}
                    </span>
                  </td>

                  {/* Last Seen */}
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-secondary">
                      {formatLastSeen(worker.last_seen_at)}
                    </span>
                  </td>

                  {/* Actions */}
                  <td className="px-4 py-3">
                    <button
                      onClick={() => onWorkerView(worker)}
                      className="p-2 text-theme-secondary hover:text-theme-primary transition-colors"
                      title="View details"
                    >
                      <Eye className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Worker Details Modal */}
      {isExpanded && expandedWorker && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-theme-surface rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-y-auto">
            <WorkerDetailsPanel
              worker={expandedWorker}
              isOpen={isExpanded}
              onClose={onCloseExpanded}
              onUpdate={onUpdateWorker}
              onDelete={onDeleteWorker}
            />
          </div>
        </div>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
            {/* Results Info */}
            <div className="text-sm text-theme-secondary">
              Showing {startIndex + 1} to {endIndex} of {workers.length} workers
            </div>

            {/* Page Size Selector */}
            <div className="flex items-center gap-2">
              <span className="text-sm text-theme-secondary">Show:</span>
              <select
                value={pagination.pageSize}
                onChange={(e) => onPaginationChange({ 
                  pageSize: parseInt(e.target.value), 
                  page: 1 
                })}
                className="px-2 py-1 border border-theme rounded bg-theme-background text-theme-primary text-sm"
              >
                {pageSizeOptions.map(size => (
                  <option key={size} value={size}>{size}</option>
                ))}
              </select>
              <span className="text-sm text-theme-secondary">per page</span>
            </div>

            {/* Pagination Controls */}
            <div className="flex items-center gap-1">
              <button
                onClick={() => goToPage(pagination.page - 1)}
                disabled={pagination.page <= 1}
                className="p-2 border border-theme rounded-lg text-theme-primary hover:bg-theme-background disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                <ChevronLeft className="w-4 h-4" />
              </button>

              {/* Page Numbers */}
              <div className="flex gap-1">
                {Array.from({ length: Math.min(5, totalPages) }, (_, i) => {
                  let pageNum: number;
                  if (totalPages <= 5) {
                    pageNum = i + 1;
                  } else if (pagination.page <= 3) {
                    pageNum = i + 1;
                  } else if (pagination.page > totalPages - 2) {
                    pageNum = totalPages - 4 + i;
                  } else {
                    pageNum = pagination.page - 2 + i;
                  }

                  return (
                    <button
                      key={pageNum}
                      onClick={() => goToPage(pageNum)}
                      className={`px-3 py-2 text-sm border border-theme rounded-lg transition-colors ${
                        pagination.page === pageNum
                          ? 'bg-theme-interactive-primary text-white border-theme-interactive-primary'
                          : 'text-theme-primary hover:bg-theme-background'
                      }`}
                    >
                      {pageNum}
                    </button>
                  );
                })}
              </div>

              <button
                onClick={() => goToPage(pagination.page + 1)}
                disabled={pagination.page >= totalPages}
                className="p-2 border border-theme rounded-lg text-theme-primary hover:bg-theme-background disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

