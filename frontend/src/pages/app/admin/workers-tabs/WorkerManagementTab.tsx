import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { WorkerFilters } from '@/features/admin/workers/components/WorkerFilters';
import { WorkerGrid } from '@/features/admin/workers/components/WorkerGrid';
import { WorkerTable } from '@/features/admin/workers/components/WorkerTable';
import { WorkerActions } from '@/features/admin/workers/components/WorkerActions';
import { workerApi } from '@/features/admin/workers/services/workerApi';
import { Plus, Grid, List } from 'lucide-react';
import type { WorkerManagementTabProps, WorkerFiltersState } from './types';

export const WorkerManagementTab: React.FC<WorkerManagementTabProps> = ({
  state,
  setState,
  canManageWorkers,
  handleFiltersChange,
  handleWorkerSelect,
  handleWorkerView,
  handleBulkAction,
  loadWorkers
}) => {
  return (
    <div className="space-y-6">
      {/* Filters and View Toggle */}
      <Card className="p-6">
        <FlexBetween className="mb-4">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Worker Management</h3>
            <p className="text-sm text-theme-secondary">
              Manage and monitor all authentication workers
            </p>
          </div>
          <FlexItemsCenter gap="sm">
            {canManageWorkers && (
              <Button
                onClick={() => setState(prev => ({ ...prev, showCreateModal: true }))}
                variant="primary"
                size="sm"
              >
                <Plus className="w-4 h-4 mr-2" />
                Create Worker
              </Button>
            )}
          </FlexItemsCenter>
        </FlexBetween>

        <div className="flex flex-col lg:flex-row gap-4 items-start lg:items-center justify-between">
          <div className="flex-1 min-w-0">
            <WorkerFilters
              filters={state.filters}
              onChange={handleFiltersChange}
              totalWorkers={state.workers.length}
              filteredWorkers={state.filteredWorkers.length}
            />
          </div>

          <div className="flex items-center gap-4">
            {/* Bulk Actions */}
            {state.selectedWorkers.size > 0 && canManageWorkers && (
              <WorkerActions
                selectedCount={state.selectedWorkers.size}
                onBulkAction={(action) => handleBulkAction(action, Array.from(state.selectedWorkers))}
              />
            )}

            {/* View Toggle */}
            <div className="flex border border-theme rounded-lg overflow-hidden">
              <button
                onClick={() => setState(prev => ({ ...prev, viewMode: 'grid' }))}
                className={`px-3 py-2 text-sm transition-colors ${
                  state.viewMode === 'grid'
                    ? 'bg-theme-interactive-primary text-theme-on-primary'
                    : 'bg-theme-background text-theme-primary hover:bg-theme-surface'
                }`}
              >
                <Grid className="w-4 h-4" />
              </button>
              <button
                onClick={() => setState(prev => ({ ...prev, viewMode: 'table' }))}
                className={`px-3 py-2 text-sm transition-colors border-l border-theme ${
                  state.viewMode === 'table'
                    ? 'bg-theme-interactive-primary text-theme-on-primary'
                    : 'bg-theme-background text-theme-primary hover:bg-theme-surface'
                }`}
              >
                <List className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      </Card>

      {/* Workers Display */}
      {state.filteredWorkers.length === 0 ? (
        <Card className="p-12 text-center">
          <div className="text-6xl mb-4">🤖</div>
          <h3 className="text-xl font-semibold text-theme-primary mb-2">No Workers Found</h3>
          <p className="text-theme-secondary mb-4">
            {state.filters.search || state.filters.status !== 'all' || state.filters.roleType !== 'all' ||
             state.filters.roles.length > 0 || state.filters.permissions.length > 0
              ? 'No workers match your current filters. Try adjusting your search criteria.'
              : 'Get started by creating your first authentication worker.'
            }
          </p>
          {canManageWorkers && state.workers.length === 0 && (
            <Button
              onClick={() => setState(prev => ({ ...prev, showCreateModal: true }))}
              variant="primary"
            >
              <Plus className="w-4 h-4 mr-2" />
              Create Your First Worker
            </Button>
          )}
        </Card>
      ) : (
        <div className="space-y-6">
          {state.viewMode === 'grid' ? (
            <WorkerGrid
              workers={state.filteredWorkers}
              selectedWorkers={state.selectedWorkers}
              onWorkerSelect={handleWorkerSelect}
              onWorkerView={handleWorkerView}
              pagination={state.pagination}
              onPaginationChange={(newPagination) =>
                setState(prev => ({ ...prev, pagination: { ...prev.pagination, ...newPagination } }))
              }
              expandedWorker={state.selectedWorker}
              isExpanded={state.showDetailsPanel}
              onUpdateWorker={async (workerId, data) => {
                await workerApi.updateWorker(workerId, data);
                await loadWorkers();
              }}
              onDeleteWorker={async (workerId) => {
                await workerApi.deleteWorker(workerId);
                await loadWorkers();
                setState(prev => ({ ...prev, showDetailsPanel: false, selectedWorker: null }));
              }}
              onCloseExpanded={() => setState(prev => ({ ...prev, showDetailsPanel: false, selectedWorker: null }))}
            />
          ) : (
            <WorkerTable
              workers={state.filteredWorkers}
              selectedWorkers={state.selectedWorkers}
              onWorkerSelect={handleWorkerSelect}
              onWorkerView={handleWorkerView}
              sortBy={state.filters.sortBy}
              sortOrder={state.filters.sortOrder}
              onSort={(sortBy: string, sortOrder: 'asc' | 'desc') =>
                handleFiltersChange({ sortBy: sortBy as WorkerFiltersState['sortBy'], sortOrder })
              }
              pagination={state.pagination}
              onPaginationChange={(newPagination) =>
                setState(prev => ({ ...prev, pagination: { ...prev.pagination, ...newPagination } }))
              }
              expandedWorker={state.selectedWorker}
              isExpanded={state.showDetailsPanel}
              onUpdateWorker={async (workerId, data) => {
                await workerApi.updateWorker(workerId, data);
                await loadWorkers();
              }}
              onDeleteWorker={async (workerId) => {
                await workerApi.deleteWorker(workerId);
                await loadWorkers();
                setState(prev => ({ ...prev, showDetailsPanel: false, selectedWorker: null }));
              }}
              onCloseExpanded={() => setState(prev => ({ ...prev, showDetailsPanel: false, selectedWorker: null }))}
            />
          )}
        </div>
      )}
    </div>
  );
};
