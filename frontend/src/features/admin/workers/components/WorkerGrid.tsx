
import { Worker, UpdateWorkerData } from '@/features/admin/workers/services/workerApi';
import { WorkerCard } from './WorkerCard';
import { WorkerDetailsPanel } from './WorkerDetailsPanel';
import { ChevronLeft, ChevronRight } from 'lucide-react';

export interface WorkerGridProps {
  workers: Worker[];
  selectedWorkers: Set<string>;
  onWorkerSelect: (workerId: string, selected: boolean) => void;
  onWorkerView: (worker: Worker) => void;
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

export const WorkerGrid: React.FC<WorkerGridProps> = ({
  workers,
  selectedWorkers,
  onWorkerSelect,
  onWorkerView,
  pagination,
  onPaginationChange,
  expandedWorker,
  isExpanded,
  onUpdateWorker,
  onDeleteWorker,
  onCloseExpanded
}) => {
  // Calculate pagination
  const totalPages = Math.ceil(workers.length / pagination.pageSize);
  const startIndex = (pagination.page - 1) * pagination.pageSize;
  const endIndex = Math.min(startIndex + pagination.pageSize, workers.length);
  const paginatedWorkers = workers.slice(startIndex, endIndex);

  const goToPage = (page: number) => {
    onPaginationChange({ page: Math.max(1, Math.min(page, totalPages)) });
  };

  const pageSizeOptions = [6, 12, 24, 48];

  return (
    <div className="space-y-6">
      {/* Worker Grid */}
      <div className="grid gap-6 grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {paginatedWorkers.map((worker, _index) => (
          <WorkerCard
            key={worker.id}
            worker={worker}
            isSelected={selectedWorkers.has(worker.id)}
            onSelect={(selected: boolean) => onWorkerSelect(worker.id, selected)}
            onView={() => onWorkerView(worker)}
          />
        ))}
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