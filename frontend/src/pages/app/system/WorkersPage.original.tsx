import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { workerAPI, Worker } from '@/features/workers/services/workerApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { WorkerDetails } from '@/features/workers/components/WorkerDetails';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Plus, RefreshCw, Download } from 'lucide-react';

// Helper function to format masked tokens with appropriate asterisks
const formatMaskedToken = (maskedToken: string): string => {
  // If token looks like "swt_****...****" format, keep it as is
  if (maskedToken.includes('_') && maskedToken.length < 25) {
    return maskedToken;
  }
  
  // For longer tokens, show first 8 chars + ****** + last 4 chars
  if (maskedToken.length > 20) {
    const start = maskedToken.substring(0, 8);
    const end = maskedToken.substring(maskedToken.length - 4);
    return `${start}******${end}`;
  }
  
  return maskedToken;
};

interface WorkersPageState {
  workers: Worker[];
  selectedWorker: Worker | null;
  selectedWorkers: Set<string>;
  loading: boolean;
  showCreateModal: boolean;
  showDetailsModal: boolean;
  showDeleteModal: boolean;
  showBulkActionsModal: boolean;
  showExportModal: boolean;
  editMode: boolean;
  searchTerm: string;
  error: string | null;
  successMessage: string | null;
  createModalLoading: boolean;
  statusFilter: 'all' | 'active' | 'suspended' | 'revoked';
  roleFilter: 'all' | 'system' | 'account';
  permissionSearch: string; // Search for specific permissions
  sortBy: 'name' | 'created_at' | 'last_seen_at' | 'request_count';
  sortOrder: 'asc' | 'desc';
  viewMode: 'grid' | 'table';
  pageSize: number;
  currentPage: number;
}

// Enhanced Worker Card Component
interface WorkerCardProps {
  worker: Worker;
  isSelected: boolean;
  onView: (worker: Worker) => void;
  onEdit: (worker: Worker) => void;
  onDelete: (worker: Worker) => void;
  onStatusChange: (worker: Worker, action: 'suspend' | 'activate' | 'revoke') => void;
  onTokenRegenerate: (worker: Worker) => void;
  onSelect: (workerId: string, selected: boolean) => void;
  viewMode: 'grid' | 'table';
}

const WorkerCard: React.FC<WorkerCardProps> = ({ 
  worker, 
  isSelected,
  onView, 
  onEdit, 
  onDelete, 
  onStatusChange, 
  onTokenRegenerate,
  onSelect,
  viewMode
}) => {
  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active': return 'bg-theme-success-background text-theme-success';
      case 'suspended': return 'bg-theme-warning-background text-theme-warning';
      case 'revoked': return 'bg-theme-error-background text-theme-error';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  // Helper to determine color based on permission types
  const getPermissionsBadgeColor = (permissions: string[]) => {
    if (permissions.some(p => p.includes('system.'))) {
      return 'bg-theme-error-background text-theme-error';
    }
    if (permissions.some(p => p.includes('admin.'))) {
      return 'bg-theme-warning-background text-theme-warning';
    }
    if (permissions.some(p => p.includes('manage') || p.includes('create') || p.includes('delete'))) {
      return 'bg-theme-success-background text-theme-success';
    }
    return 'bg-theme-info-background text-theme-info';
  };


  // Render table row for table view
  if (viewMode === 'table') {
    return (
      <tr className="hover:bg-theme-background transition-colors">
        <td className="px-4 py-3">
          <div className="flex items-center space-x-3">
            <input
              type="checkbox"
              checked={isSelected}
              onChange={(e) => onSelect(worker.id, e.target.checked)}
              className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
            />
            <div>
              <div className="font-medium text-theme-primary">{worker.name}</div>
              {worker.description && (
                <div className="text-sm text-theme-secondary">{worker.description}</div>
              )}
              <div className="text-xs text-theme-secondary">
                {worker.account_name}
              </div>
            </div>
          </div>
        </td>
        <td className="px-4 py-3">
          <span className={`px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(worker.status)}`}>
            {worker.status}
          </span>
        </td>
        <td className="px-4 py-3">
          <div className="flex flex-wrap gap-1">
            {worker.permissions.length > 0 ? (
              worker.permissions.slice(0, 3).map((permission, index) => (
                <span 
                  key={index}
                  className={`px-2 py-1 rounded-full text-xs font-medium ${getPermissionsBadgeColor([permission])}`}
                  title={permission}
                >
                  {permission.split('.').pop()}
                </span>
              ))
            ) : (
              <span className="text-theme-secondary text-xs">No permissions</span>
            )}
            {worker.permissions.length > 3 && (
              <span className="px-2 py-1 rounded-full text-xs font-medium bg-theme-surface text-theme-secondary">
                +{worker.permissions.length - 3} more
              </span>
            )}
          </div>
        </td>
        <td className="px-4 py-3 text-sm text-theme-primary">
          {worker.request_count.toLocaleString()}
        </td>
        <td className="px-4 py-3 text-sm text-theme-secondary">
          {worker.last_seen_at ? new Date(worker.last_seen_at).toLocaleDateString() : 'Never'}
        </td>
        <td className="px-4 py-3">
          <div className="flex space-x-1">
            <button
              onClick={() => onView(worker)}
              className="px-2 py-1 bg-theme-interactive-primary hover:bg-theme-interactive-primary/80 text-white rounded text-xs transition-colors"
              title="View Details"
            >
              View
            </button>
            {worker.status === 'active' && (
              <button
                onClick={() => onEdit(worker)}
                className="px-2 py-1 bg-theme-surface hover:bg-theme-background border border-theme text-theme-primary rounded text-xs transition-colors"
                title="Edit Worker"
              >
                Edit
              </button>
            )}
            <button
              onClick={() => onDelete(worker)}
              className="px-2 py-1 bg-theme-error-background hover:bg-theme-error-background/80 text-theme-error rounded text-xs transition-colors"
              title="Delete Worker"
            >
              🗑️
            </button>
          </div>
        </td>
      </tr>
    );
  }

  // Render card for grid view
  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 sm:p-6 hover:shadow-lg transition-shadow duration-200">
      <div className="flex justify-between items-start mb-4">
        <div className="flex-1">
          <h3 className="text-lg font-semibold text-theme-primary mb-1">{worker.name}</h3>
          {worker.description && (
            <p className="text-theme-secondary text-sm mb-2">{worker.description}</p>
          )}
          <div className="flex flex-wrap gap-2 mb-3">
            <span className={`px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(worker.status)}`}>
              {worker.status}
            </span>
            <div className="flex flex-wrap gap-1">
              {worker.permissions.slice(0, 3).map((permission, index) => (
                <span 
                  key={index}
                  className="px-2 py-1 rounded-full text-xs font-medium bg-theme-surface text-theme-primary"
                  title={permission}
                >
                  {permission.split('.').pop()}
                </span>
              ))}
              {worker.permissions.length > 3 && (
                <span className="px-2 py-1 rounded-full text-xs font-medium bg-theme-info-background text-theme-info">
                  +{worker.permissions.length - 3} more
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      <div className="space-y-2 mb-4">
        <div className="text-sm">
          <span className="text-theme-secondary">Token:</span>
          <code className="ml-2 bg-theme-background px-2 py-1 rounded text-xs font-mono">
            {formatMaskedToken(worker.masked_token)}
          </code>
        </div>
        <div className="text-sm">
          <span className="text-theme-secondary">Account:</span>
          <span className="ml-2 text-theme-primary">{worker.account_name}</span>
        </div>
        <div className="text-sm">
          <span className="text-theme-secondary">Requests:</span>
          <span className="ml-2 text-theme-primary">{worker.request_count.toLocaleString()}</span>
        </div>
        {worker.last_seen_at && (
          <div className="text-sm">
            <span className="text-theme-secondary">Last Seen:</span>
            <span className="ml-2 text-theme-primary">
              {new Date(worker.last_seen_at).toLocaleDateString()}
            </span>
          </div>
        )}
      </div>

      <div className="flex flex-wrap gap-2 sm:gap-3">
        <button
          onClick={() => onView(worker)}
          className="px-2 py-1 sm:px-3 sm:py-1 bg-theme-interactive-primary hover:bg-theme-interactive-primary/80 text-white rounded text-xs sm:text-sm transition-colors"
        >
          View Details
        </button>
        
        {worker.status === 'active' && (
          <button
            onClick={() => onEdit(worker)}
            className="px-2 py-1 sm:px-3 sm:py-1 bg-theme-surface hover:bg-theme-background border border-theme text-theme-primary rounded text-xs sm:text-sm transition-colors"
            title="Edit Worker"
          >
            Edit
          </button>
        )}

        {worker.status === 'active' && (
          <button
            onClick={() => onStatusChange(worker, 'suspend')}
            className="px-2 py-1 sm:px-3 sm:py-1 bg-theme-warning-background hover:bg-theme-warning-background/80 text-theme-warning rounded text-xs sm:text-sm transition-colors"
            title="Suspend Worker"
          >
            Suspend
          </button>
        )}

        {worker.status === 'suspended' && (
          <button
            onClick={() => onStatusChange(worker, 'activate')}
            className="px-2 py-1 sm:px-3 sm:py-1 bg-theme-success-background hover:bg-theme-success-background/80 text-theme-success rounded text-xs sm:text-sm transition-colors"
            title="Activate Worker"
          >
            Activate
          </button>
        )}

        <button
          onClick={() => onTokenRegenerate(worker)}
          className="px-2 py-1 sm:px-3 sm:py-2 bg-theme-surface hover:bg-theme-background border border-theme text-theme-primary rounded text-xs sm:text-sm transition-colors"
          title="Regenerate Token"
        >
          🔄 New Token
        </button>
        
        <button
          onClick={() => onDelete(worker)}
          className="px-2 py-1 sm:px-3 sm:py-2 bg-theme-error-background hover:bg-theme-error-background/80 text-theme-error rounded text-xs sm:text-sm transition-colors"
          title="Delete Worker"
        >
          🗑️
        </button>
      </div>
    </div>
  );
};

// Create Worker Modal Component
interface CreateWorkerModalProps {
  onClose: () => void;
  onCreate: (workerData: any) => void;
}

const CreateWorkerModal: React.FC<CreateWorkerModalProps> = ({ onClose, onCreate }) => {
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    roles: ['member'] as string[]
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      await onCreate(formData);
      onClose();
    } catch (error) {
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg p-6 w-full max-w-md">
        <div className="flex justify-between items-center mb-4">
          <h2 className="text-xl font-semibold text-theme-primary">Create New Worker</h2>
          <button
            onClick={onClose}
            className="text-theme-secondary hover:text-theme-primary"
          >
            ✕
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Worker Name
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              placeholder="Enter worker name"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Description
            </label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              placeholder="Enter description (optional)"
              rows={3}
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Roles
            </label>
            <div className="space-y-2 max-h-32 overflow-y-auto border border-theme rounded p-3 bg-theme-background">
              {[
                { name: 'member', display: 'Member' },
                { name: 'developer', display: 'App Developer' },
                { name: 'billing_admin', display: 'Billing Administrator' },
                { name: 'admin', display: 'Administrator' },
                { name: 'super_admin', display: 'Super Administrator' },
                { name: 'system_worker', display: 'System Worker' },
                { name: 'task_worker', display: 'Task Worker' }
              ].map((role) => (
                <label key={role.name} className="flex items-center space-x-2">
                  <input
                    type="checkbox"
                    checked={formData.roles.includes(role.name)}
                    onChange={(e) => {
                      const newRoles = e.target.checked
                        ? [...formData.roles, role.name]
                        : formData.roles.filter(r => r !== role.name);
                      setFormData(prev => ({ ...prev, roles: newRoles }));
                    }}
                    className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                  />
                  <span className="text-sm text-theme-primary">{role.display}</span>
                </label>
              ))}
            </div>
            <p className="text-xs text-theme-secondary mt-1">
              Select one or more roles. Permissions are inherited from roles.
            </p>
          </div>

          <div className="flex justify-end space-x-3 pt-4">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 border border-theme rounded-md text-theme-secondary hover:text-theme-primary transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading || !formData.name.trim()}
              className="px-4 py-2 bg-theme-interactive-primary hover:bg-theme-interactive-primary/80 text-white rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? 'Creating...' : '✨ Create Worker'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export const WorkersPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);

  // Check if user has permission to view system workers
  const canViewWorkers = hasPermissions(user, ['system.workers.read']);
  const canManageWorkers = hasPermissions(user, ['system.workers.create', 'system.workers.edit', 'system.workers.delete']);

  const [state, setState] = useState<WorkersPageState>({
    workers: [],
    selectedWorker: null,
    selectedWorkers: new Set<string>(),
    loading: true,
    showCreateModal: false,
    showDetailsModal: false,
    showDeleteModal: false,
    showBulkActionsModal: false,
    showExportModal: false,
    editMode: false,
    searchTerm: '',
    error: null,
    successMessage: null,
    createModalLoading: false,
    statusFilter: 'all',
    roleFilter: 'all',
    permissionSearch: '',
    sortBy: 'created_at',
    sortOrder: 'desc',
    viewMode: 'grid',
    pageSize: 12,
    currentPage: 1
  });

  const loadWorkers = useCallback(async () => {
    setState(prev => ({ ...prev, loading: true, error: null }));
    try {
      const response = await workerAPI.getWorkers();
      setState(prev => ({
        ...prev,
        workers: response.workers || [], // Ensure workers is always an array
        loading: false
      }));
    } catch (error: any) {
      const errorMessage = error.message || 'Failed to load workers';
      setState(prev => ({
        ...prev,
        error: errorMessage,
        workers: [], // Set workers to empty array on error to prevent undefined access
        loading: false
      }));
      // Error is already set in state
    }
  }, []);

  useEffect(() => {
    loadWorkers();
  }, [loadWorkers]);

  // Keyboard shortcuts for enhanced user experience
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      // Don't trigger shortcuts if user is typing in an input
      if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) {
        return;
      }

      if (event.ctrlKey || event.metaKey) {
        switch (event.key.toLowerCase()) {
          case 'r':
            event.preventDefault();
            if (!state.loading) {
              loadWorkers();
            }
            break;
          case 'n':
            event.preventDefault();
            setState(prev => ({ ...prev, showCreateModal: true }));
            break;
          case 'e':
            event.preventDefault();
            if ((state.workers || []).length > 0) {
              setState(prev => ({ ...prev, showExportModal: true }));
            }
            break;
        }
      }

      // Escape key to close modals
      if (event.key === 'Escape') {
        setState(prev => ({
          ...prev,
          showCreateModal: false,
          showDetailsModal: false,
          showDeleteModal: false,
          showBulkActionsModal: false,
          showExportModal: false
        }));
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [state.loading, loadWorkers, (state.workers || []).length]);

  // Enhanced handlers
  const handleWorkerCreate = async (workerData: any) => {
    try {
      await workerAPI.createWorker(workerData);
      await loadWorkers();
      setState(prev => ({ ...prev, showCreateModal: false }));
      setState(prev => ({ ...prev, successMessage: `Worker "${workerData.name}" created successfully` }));
      setTimeout(() => setState(prev => ({ ...prev, successMessage: null })), 3000);
    } catch (error: any) {
      // Error will be handled by the modal
      throw error;
    }
  };

  const handleWorkerSelect = useCallback((workerId: string, selected: boolean) => {
    setState(prev => {
      const newSelected = new Set(prev.selectedWorkers);
      if (selected) {
        newSelected.add(workerId);
      } else {
        newSelected.delete(workerId);
      }
      return { ...prev, selectedWorkers: newSelected };
    });
  }, []);

  const handleSort = useCallback((column: 'name' | 'created_at' | 'last_seen_at' | 'request_count') => {
    setState(prev => ({
      ...prev,
      sortBy: column,
      sortOrder: prev.sortBy === column && prev.sortOrder === 'asc' ? 'desc' : 'asc'
    }));
  }, []);

  const handleSelectAll = useCallback((selected: boolean, workers: Worker[]) => {
    setState(prev => ({
      ...prev,
      selectedWorkers: selected ? new Set(workers.map(w => w.id)) : new Set()
    }));
  }, []);

  const handleBulkAction = async (action: 'suspend' | 'activate' | 'delete', workerIds: string[]) => {
    try {
      const promises = workerIds.map(id => {
        switch (action) {
          case 'suspend': return workerAPI.suspendWorker(id);
          case 'activate': return workerAPI.activateWorker(id);
          case 'delete': return workerAPI.deleteWorker(id);
          default: throw new Error(`Unknown action: ${action}`);
        }
      });
      
      await Promise.all(promises);
      await loadWorkers();
      setState(prev => ({ ...prev, selectedWorkers: new Set(), showBulkActionsModal: false }));
      setState(prev => ({ ...prev, successMessage: `Successfully ${action}d ${workerIds.length} worker(s)` }));
      setTimeout(() => setState(prev => ({ ...prev, successMessage: null })), 3000);
    } catch (error: any) {
      setState(prev => ({ ...prev, error: `Failed to ${action} workers: ${error.message}` }));
      setTimeout(() => setState(prev => ({ ...prev, error: null })), 5000);
    }
  };

  const handleExport = async (format: 'csv' | 'json') => {
    try {
      const dataToExport = state.selectedWorkers.size > 0 
        ? state.workers.filter(w => state.selectedWorkers.has(w.id))
        : filteredAndSortedWorkers;
      
      const exportData = dataToExport.map(worker => ({
        name: worker.name,
        description: worker.description || '',
        account_type: worker.account_name === 'System' ? 'system' : 'account',
        permissions: worker.permissions,
        status: worker.status,
        account: worker.account_name,
        requests: worker.request_count,
        lastSeen: worker.last_seen_at || 'Never',
        created: worker.created_at
      }));
      
      if (format === 'csv') {
        const csv = [Object.keys(exportData[0]).join(',')]
          .concat(exportData.map(row => Object.values(row).map(val => `"${val}"`).join(',')))
          .join('\n');
        
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `workers-${new Date().toISOString().split('T')[0]}.csv`;
        a.click();
        URL.revokeObjectURL(url);
      } else {
        const json = JSON.stringify(exportData, null, 2);
        const blob = new Blob([json], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `workers-${new Date().toISOString().split('T')[0]}.json`;
        a.click();
        URL.revokeObjectURL(url);
      }
      
      setState(prev => ({ ...prev, showExportModal: false }));
      setState(prev => ({ ...prev, successMessage: `Workers exported as ${format.toUpperCase()}` }));
      setTimeout(() => setState(prev => ({ ...prev, successMessage: null })), 3000);
    } catch (error: any) {
      setState(prev => ({ ...prev, error: `Failed to export workers: ${error.message}` }));
      setTimeout(() => setState(prev => ({ ...prev, error: null })), 5000);
    }
  };

  const handleWorkerEdit = (worker: Worker) => {
    setState(prev => ({ ...prev, selectedWorker: worker, showDetailsModal: true, editMode: true }));
  };

  const handleWorkerView = (worker: Worker) => {
    setState(prev => ({ ...prev, selectedWorker: worker, showDetailsModal: true, editMode: false }));
  };

  const handleWorkerDelete = (worker: Worker) => {
    setState(prev => ({ ...prev, selectedWorker: worker, showDeleteModal: true }));
  };

  const confirmDelete = async () => {
    if (!state.selectedWorker) return;
    try {
      await workerAPI.deleteWorker(state.selectedWorker.id);
      await loadWorkers();
      setState(prev => ({ ...prev, showDeleteModal: false, selectedWorker: null }));
    } catch (error: any) {
    }
  };

  const handleStatusChange = async (worker: Worker, action: 'suspend' | 'activate' | 'revoke') => {
    try {
      switch (action) {
        case 'suspend':
          await workerAPI.suspendWorker(worker.id);
          break;
        case 'activate':
          await workerAPI.activateWorker(worker.id);
          break;
        case 'revoke':
          await workerAPI.revokeWorker(worker.id);
          break;
      }
      await loadWorkers();
    } catch (error: any) {
    }
  };

  const handleTokenRegenerate = async (worker: Worker) => {
    try {
      const response = await workerAPI.regenerateToken(worker.id);
      await loadWorkers();
      
      // Show the new token to the user
      alert(`New token generated: ${response.new_token}`);
    } catch (error: any) {
    }
  };


  // Enhanced filtering, sorting, and pagination
  const filteredAndSortedWorkers = useMemo(() => {
    // Ensure workers is always an array to prevent undefined.length errors
    const workers = state.workers || [];
    let filtered = workers.filter(worker => {
      const matchesSearch = worker.name.toLowerCase().includes(state.searchTerm.toLowerCase()) ||
                           worker.description?.toLowerCase().includes(state.searchTerm.toLowerCase()) ||
                           worker.account_name.toLowerCase().includes(state.searchTerm.toLowerCase()) ||
                           worker.masked_token.toLowerCase().includes(state.searchTerm.toLowerCase());
      
      const matchesStatus = state.statusFilter === 'all' || worker.status === state.statusFilter;
      const matchesRole = state.roleFilter === 'all' || 
        (state.roleFilter === 'system' && worker.account_name === 'System') ||
        (state.roleFilter === 'account' && worker.account_name !== 'System');
      const matchesPermission = !state.permissionSearch || 
        worker.permissions.some(permission => 
          permission.toLowerCase().includes(state.permissionSearch.toLowerCase())
        );
      
      return matchesSearch && matchesStatus && matchesRole && matchesPermission;
    });

    // Sort workers
    filtered.sort((a, b) => {
      let comparison = 0;
      
      switch (state.sortBy) {
        case 'name':
          comparison = a.name.localeCompare(b.name);
          break;
        case 'created_at':
          comparison = new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
          break;
        case 'last_seen_at':
          const aTime = a.last_seen_at ? new Date(a.last_seen_at).getTime() : 0;
          const bTime = b.last_seen_at ? new Date(b.last_seen_at).getTime() : 0;
          comparison = aTime - bTime;
          break;
        case 'request_count':
          comparison = a.request_count - b.request_count;
          break;
        default:
          comparison = 0;
      }
      
      return state.sortOrder === 'desc' ? -comparison : comparison;
    });

    return filtered;
  }, [state.workers, state.searchTerm, state.statusFilter, state.roleFilter, state.permissionSearch, state.sortBy, state.sortOrder]);

  // Pagination
  const totalPages = Math.ceil(filteredAndSortedWorkers.length / state.pageSize);
  const startIndex = (state.currentPage - 1) * state.pageSize;
  const paginatedWorkers = filteredAndSortedWorkers.slice(startIndex, startIndex + state.pageSize);

  // Enhanced statistics
  const statistics = useMemo(() => {
    // Ensure workers is always an array to prevent undefined access errors
    const workers = state.workers || [];
    const total = workers.length;
    const active = workers.filter(w => w.status === 'active').length;
    const suspended = workers.filter(w => w.status === 'suspended').length;
    const revoked = workers.filter(w => w.status === 'revoked').length;
    const system = workers.filter(w => w.account_name === 'System').length;
    const account = workers.filter(w => w.account_name !== 'System').length;
    const recentlyActive = workers.filter(w => {
      if (!w.last_seen_at) return false;
      const hoursAgo = (Date.now() - new Date(w.last_seen_at).getTime()) / (1000 * 60 * 60);
      return hoursAgo < 24;
    }).length;
    const totalRequests = workers.reduce((sum, w) => sum + w.request_count, 0);
    
    return { total, active, suspended, revoked, system, account, recentlyActive, totalRequests };
  }, [state.workers]);


  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadWorkers,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: state.loading
    },
    {
      id: 'export',
      label: 'Export',
      onClick: () => setState(prev => ({ ...prev, showExportModal: true })),
      variant: 'secondary',
      icon: Download,
      disabled: state.loading || filteredAndSortedWorkers.length === 0
    },
    ...(canManageWorkers ? [{
      id: 'create',
      label: 'Create Worker',
      onClick: () => setState(prev => ({ ...prev, showCreateModal: true })),
      variant: 'primary' as const,
      icon: Plus,
      disabled: state.loading
    }] : [])
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'System', icon: '🔧' },
    { label: 'Workers', icon: '🤖' }
  ];

  // Redirect if user doesn't have permission
  if (!canViewWorkers) {
    return <Navigate to="/app" replace />;
  }

  return (
    <PageContainer
      title="Worker Management"
      description="Manage authentication workers, permissions, and monitor activity. Shortcuts: Ctrl+R (Refresh), Ctrl+N (New), Ctrl+E (Export), Esc (Close modals)"
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      
      {/* Success Message */}
      {state.successMessage && (
        <div className="bg-theme-success-background border border-theme-success rounded-lg p-4 flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <span className="text-xl">✅</span>
            <span className="text-theme-success font-medium">{state.successMessage}</span>
          </div>
          <button
            onClick={() => setState(prev => ({ ...prev, successMessage: null }))}
            className="text-theme-success hover:text-theme-success/80"
          >
            ✕
          </button>
        </div>
      )}

      {/* Error Message */}
      {state.error && (
        <div className="bg-theme-error-background border border-theme-error rounded-lg p-4 flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <span className="text-xl">❌</span>
            <span className="text-theme-error font-medium">{state.error}</span>
          </div>
          <button
            onClick={() => setState(prev => ({ ...prev, error: null }))}
            className="text-theme-error hover:text-theme-error/80"
          >
            ✕
          </button>
        </div>
      )}

      {/* Bulk Actions Section */}
      {state.selectedWorkers.size > 0 && (
        <div className="bg-theme-warning-background border border-theme-warning rounded-lg p-4 flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <span className="text-xl">⚙️</span>
            <span className="text-theme-warning font-medium">
              {state.selectedWorkers.size} worker(s) selected
            </span>
          </div>
          <button
            onClick={() => setState(prev => ({ ...prev, showBulkActionsModal: true }))}
            className="px-4 py-2 bg-theme-warning text-white rounded-lg hover:bg-theme-warning/80 transition-colors"
          >
            Bulk Actions
          </button>
        </div>
      )}

      {/* Enhanced Statistics Dashboard */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-6 gap-4">
        <div className="bg-theme-surface rounded-lg p-4 border border-theme hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-primary">{statistics.total}</div>
              <p className="text-theme-secondary text-sm">Total Workers</p>
            </div>
            <div className="text-2xl">🤖</div>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-4 border border-theme hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-success">{statistics.active}</div>
              <p className="text-theme-secondary text-sm">Active</p>
            </div>
            <div className="text-2xl">✅</div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg p-4 border border-theme hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-error">{statistics.system}</div>
              <p className="text-theme-secondary text-sm">System</p>
            </div>
            <div className="text-2xl">⚙️</div>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-4 border border-theme hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-info">{statistics.account}</div>
              <p className="text-theme-secondary text-sm">Account</p>
            </div>
            <div className="text-2xl">👥</div>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-4 border border-theme hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-warning">{statistics.recentlyActive}</div>
              <p className="text-theme-secondary text-sm">Recent Activity</p>
            </div>
            <div className="text-2xl">🔥</div>
          </div>
        </div>
        
        <div className="bg-theme-surface rounded-lg p-4 border border-theme hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-2xl font-bold text-theme-primary">{statistics.totalRequests.toLocaleString()}</div>
              <p className="text-theme-secondary text-sm">Total Requests</p>
            </div>
            <div className="text-2xl">📊</div>
          </div>
        </div>
      </div>

      {/* Enhanced Filters and Controls */}
      <div className="bg-theme-surface rounded-lg p-4 border border-theme">
        <div className="flex flex-col lg:flex-row gap-4">
          <div className="flex-1">
            <div className="relative">
              <input
                type="text"
                placeholder="Search workers by name, description, account, or token..."
                value={state.searchTerm}
                onChange={(e) => setState(prev => ({ ...prev, searchTerm: e.target.value, currentPage: 1 }))}
                className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              />
              <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                <span className="text-theme-secondary">🔍</span>
              </div>
              {state.searchTerm && (
                <button
                  onClick={() => setState(prev => ({ ...prev, searchTerm: '', currentPage: 1 }))}
                  className="absolute inset-y-0 right-0 pr-3 flex items-center text-theme-secondary hover:text-theme-primary"
                >
                  ✕
                </button>
              )}
            </div>
          </div>
          
          <div className="flex flex-wrap gap-3">
            <select
              value={state.statusFilter}
              onChange={(e) => setState(prev => ({ ...prev, statusFilter: e.target.value as any, currentPage: 1 }))}
              className="px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            >
              <option value="all">🔄 All Status</option>
              <option value="active">✅ Active</option>
              <option value="suspended">⏸️ Suspended</option>
              <option value="revoked">❌ Revoked</option>
            </select>

            <select
              value={state.roleFilter}
              onChange={(e) => setState(prev => ({ ...prev, roleFilter: e.target.value as any, currentPage: 1 }))}
              className="px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            >
              <option value="all">🔄 All Roles</option>
              <option value="system">⚙️ System</option>
              <option value="account">👥 Account</option>
            </select>

            <input
              type="text"
              placeholder="Search permissions..."
              value={state.permissionSearch}
              onChange={(e) => setState(prev => ({ ...prev, permissionSearch: e.target.value, currentPage: 1 }))}
              className="px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            />
            
            <div className="flex border border-theme rounded-lg overflow-hidden">
              <button
                onClick={() => setState(prev => ({ ...prev, viewMode: 'grid' }))}
                className={`px-3 py-2 text-sm transition-colors ${
                  state.viewMode === 'grid'
                    ? 'bg-theme-interactive-primary text-white'
                    : 'bg-theme-background text-theme-primary hover:bg-theme-surface'
                }`}
              >
                📋 Grid
              </button>
              <button
                onClick={() => setState(prev => ({ ...prev, viewMode: 'table' }))}
                className={`px-3 py-2 text-sm transition-colors border-l border-theme ${
                  state.viewMode === 'table'
                    ? 'bg-theme-interactive-primary text-white'
                    : 'bg-theme-background text-theme-primary hover:bg-theme-surface'
                }`}
              >
                📈 Table
              </button>
            </div>
          </div>
        </div>
        
        {/* Sort and Results Info */}
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 mt-4 pt-3 border-t border-theme">
          <div className="flex items-center gap-2 text-sm text-theme-secondary">
            <span>Showing {paginatedWorkers.length} of {filteredAndSortedWorkers.length} workers</span>
            {state.searchTerm && <span>(“{state.searchTerm}”)</span>}
          </div>
          
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2">
              <label className="text-sm text-theme-secondary">Sort by:</label>
              <select
                value={state.sortBy}
                onChange={(e) => handleSort(e.target.value as any)}
                className="px-2 py-1 border border-theme rounded bg-theme-background text-theme-primary text-sm focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
              >
                <option value="created_at">Created Date</option>
                <option value="name">Name</option>
                <option value="last_seen_at">Last Seen</option>
                <option value="request_count">Request Count</option>
              </select>
              <button
                onClick={() => setState(prev => ({ ...prev, sortOrder: prev.sortOrder === 'asc' ? 'desc' : 'asc' }))}
                className="text-theme-secondary hover:text-theme-primary"
              >
                {state.sortOrder === 'asc' ? '↑' : '↓'}
              </button>
            </div>
            
            <div className="flex items-center gap-2">
              <label className="text-sm text-theme-secondary">Per page:</label>
              <select
                value={state.pageSize}
                onChange={(e) => setState(prev => ({ ...prev, pageSize: parseInt(e.target.value), currentPage: 1 }))}
                className="px-2 py-1 border border-theme rounded bg-theme-background text-theme-primary text-sm focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
              >
                <option value="6">6</option>
                <option value="12">12</option>
                <option value="24">24</option>
                <option value="48">48</option>
              </select>
            </div>
          </div>
        </div>
      </div>

      {/* Loading State */}
      {state.loading && (
        <div className="flex justify-center py-8">
          <LoadingSpinner size="lg" />
        </div>
      )}

      {/* Error State */}
      {state.error && (
        <div className="text-center py-8">
          <div className="bg-theme-error-background rounded-lg p-4 max-w-md mx-auto">
            <p className="text-theme-error-dark font-medium">Error Loading Workers</p>
            <p className="text-theme-error text-sm mt-1">{state.error}</p>
            <button
              onClick={loadWorkers}
              className="mt-3 px-4 py-2 bg-theme-error hover:bg-theme-error-dark text-white rounded transition-colors"
            >
              Try Again
            </button>
          </div>
        </div>
      )}

      {/* Workers Display */}
      {paginatedWorkers.length === 0 && !state.loading && !state.error ? (
        <div className="text-center py-12">
          <div className="bg-theme-surface rounded-lg p-8 max-w-md mx-auto border border-theme">
            <div className="text-6xl mb-4">🤖</div>
            <h3 className="text-xl font-semibold text-theme-primary mb-2">No Workers Found</h3>
            <p className="text-theme-secondary mb-4">
              {state.searchTerm || state.statusFilter !== 'all' || state.roleFilter !== 'all' || state.permissionSearch
                ? 'No workers match your current filters. Try adjusting your search criteria.'
                : 'Get started by creating your first authentication worker.'
              }
            </p>
            {(!state.searchTerm && state.statusFilter === 'all' && state.roleFilter === 'all' && !state.permissionSearch) && (
              <button
                onClick={() => setState(prev => ({ ...prev, showCreateModal: true }))}
                className="px-6 py-3 bg-theme-interactive-primary hover:bg-theme-interactive-primary/80 text-white rounded-lg transition-colors font-medium"
              >
                ✨ Create Your First Worker
              </button>
            )}
            {(state.searchTerm || state.statusFilter !== 'all' || state.roleFilter !== 'all' || state.permissionSearch) && (
              <button
                onClick={() => setState(prev => ({ 
                  ...prev, 
                  searchTerm: '', 
                  statusFilter: 'all', 
                  permissionFilter: 'all', 
                  roleFilter: 'all',
                  currentPage: 1
                }))}
                className="px-4 py-2 bg-theme-surface border border-theme text-theme-primary rounded-lg hover:bg-theme-background transition-colors"
              >
                🔄 Clear Filters
              </button>
            )}
          </div>
        </div>
      ) : (
        <div className="space-y-8">
          {state.viewMode === 'table' ? (
            <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead className="bg-theme-background border-b border-theme">
                    <tr>
                      <th className="px-4 py-3 text-left">
                        <div className="flex items-center space-x-2">
                          <input
                            type="checkbox"
                            checked={state.selectedWorkers.size === paginatedWorkers.length && paginatedWorkers.length > 0}
                            onChange={(e) => handleSelectAll(e.target.checked, paginatedWorkers)}
                            className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                          />
                          <span className="text-sm font-medium text-theme-primary">Worker</span>
                        </div>
                      </th>
                      <th className="px-4 py-3 text-left text-sm font-medium text-theme-primary">Status</th>
                      <th className="px-4 py-3 text-left text-sm font-medium text-theme-primary">Role</th>
                      <th className="px-4 py-3 text-left text-sm font-medium text-theme-primary">Permissions</th>
                      <th className="px-4 py-3 text-left text-sm font-medium text-theme-primary">Requests</th>
                      <th className="px-4 py-3 text-left text-sm font-medium text-theme-primary">Activity</th>
                      <th className="px-4 py-3 text-left text-sm font-medium text-theme-primary">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-theme">
                    {paginatedWorkers.map((worker) => (
                      <WorkerCard
                        key={worker.id}
                        worker={worker}
                        isSelected={state.selectedWorkers.has(worker.id)}
                        onView={handleWorkerView}
                        onEdit={handleWorkerEdit}
                        onDelete={handleWorkerDelete}
                        onStatusChange={handleStatusChange}
                        onTokenRegenerate={handleTokenRegenerate}
                        onSelect={handleWorkerSelect}
                        viewMode="table"
                      />
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-2 xl:grid-cols-3 gap-4 lg:gap-6">
              {paginatedWorkers.map((worker) => (
                <WorkerCard
                  key={worker.id}
                  worker={worker}
                  isSelected={state.selectedWorkers.has(worker.id)}
                  onView={handleWorkerView}
                  onEdit={handleWorkerEdit}
                  onDelete={handleWorkerDelete}
                  onStatusChange={handleStatusChange}
                  onTokenRegenerate={handleTokenRegenerate}
                  onSelect={handleWorkerSelect}
                  viewMode="grid"
                />
              ))}
            </div>
          )}
          
          {/* Pagination */}
          {totalPages > 1 && (
            <div className="bg-theme-surface rounded-lg p-4 border border-theme">
              <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
                <div className="text-sm text-theme-secondary">
                  Showing {startIndex + 1} to {Math.min(startIndex + state.pageSize, filteredAndSortedWorkers.length)} of {filteredAndSortedWorkers.length} workers
                </div>
                
                <div className="flex items-center space-x-2">
                  <button
                    onClick={() => setState(prev => ({ ...prev, currentPage: prev.currentPage - 1 }))}
                    disabled={state.currentPage <= 1}
                    className="px-3 py-2 border border-theme rounded-lg text-theme-primary hover:bg-theme-background disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                  >
                    ← Previous
                  </button>
                  
                  {Array.from({ length: Math.min(5, totalPages) }, (_, i) => {
                    const pageNum = state.currentPage <= 3 
                      ? i + 1 
                      : state.currentPage > totalPages - 2 
                        ? totalPages - 4 + i 
                        : state.currentPage - 2 + i;
                    
                    if (pageNum < 1 || pageNum > totalPages) return null;
                    
                    return (
                      <button
                        key={pageNum}
                        onClick={() => setState(prev => ({ ...prev, currentPage: pageNum }))}
                        className={`px-3 py-2 rounded-lg transition-colors ${
                          pageNum === state.currentPage
                            ? 'bg-theme-interactive-primary text-white'
                            : 'border border-theme text-theme-primary hover:bg-theme-background'
                        }`}
                      >
                        {pageNum}
                      </button>
                    );
                  })}
                  
                  <button
                    onClick={() => setState(prev => ({ ...prev, currentPage: prev.currentPage + 1 }))}
                    disabled={state.currentPage >= totalPages}
                    className="px-3 py-2 border border-theme rounded-lg text-theme-primary hover:bg-theme-background disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                  >Next →</button>
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Create Worker Modal */}
      {state.showCreateModal && (
        <CreateWorkerModal
          onClose={() => setState(prev => ({ ...prev, showCreateModal: false }))}
          onCreate={handleWorkerCreate}
        />
      )}

      {/* Worker Details Modal */}
      {state.showDetailsModal && state.selectedWorker && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-4xl max-h-[90vh] overflow-y-auto">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-semibold text-theme-primary">Worker Details</h2>
              <button
                onClick={() => setState(prev => ({ ...prev, showDetailsModal: false, selectedWorker: null, editMode: false }))}
                className="text-theme-secondary hover:text-theme-primary"
              >
                ✕
              </button>
            </div>
            
            <WorkerDetails
              worker={state.selectedWorker}
              editMode={state.editMode}
              onWorkerUpdate={async (workerId: string, data: any) => {
                await workerAPI.updateWorker(workerId, data);
                await loadWorkers();
                setState(prev => ({ ...prev, showDetailsModal: false, selectedWorker: null, editMode: false }));
              }}
              onTokenRegenerate={async (workerId: string) => {
                const response = await workerAPI.regenerateToken(workerId);
                await loadWorkers();
                return response.new_token;
              }}
              onStatusChange={async (workerId: string, action: 'suspend' | 'activate' | 'revoke') => {
                await handleStatusChange(state.selectedWorker!, action);
              }}
            />
          </div>
        </div>
      )}

      {/* Delete Confirmation Modal */}
      {state.showDeleteModal && state.selectedWorker && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-md border border-theme">
            <div className="mb-6">
              <div className="flex items-center space-x-3 mb-4">
                <div className="w-12 h-12 bg-theme-error-background rounded-full flex items-center justify-center">
                  <span className="text-2xl">⚠️</span>
                </div>
                <div>
                  <h2 className="text-xl font-semibold text-theme-primary">Delete Worker</h2>
                  <p className="text-theme-secondary text-sm">This action cannot be undone</p>
                </div>
              </div>
              <p className="text-theme-secondary">
                Are you sure you want to delete worker <strong>"{state.selectedWorker.name}"</strong>? 
                All associated tokens and activity history will be permanently removed.
              </p>
            </div>
            <div className="flex justify-end space-x-3">
              <button
                onClick={() => setState(prev => ({ ...prev, showDeleteModal: false, selectedWorker: null }))}
                className="px-4 py-2 border border-theme rounded-lg text-theme-secondary hover:text-theme-primary transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={confirmDelete}
                className="px-4 py-2 bg-theme-error hover:bg-theme-error/80 text-white rounded-lg transition-colors font-medium"
              >
                🗑️ Delete Worker
              </button>
            </div>
          </div>
        </div>
      )}
      
      {/* Bulk Actions Modal */}
      {state.showBulkActionsModal && state.selectedWorkers.size > 0 && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-md border border-theme">
            <div className="mb-6">
              <h2 className="text-xl font-semibold text-theme-primary mb-2">Bulk Actions</h2>
              <p className="text-theme-secondary">
                {state.selectedWorkers.size} worker(s) selected. Choose an action to apply:
              </p>
            </div>
            
            <div className="space-y-3 mb-6">
              <button
                onClick={() => handleBulkAction('suspend', Array.from(state.selectedWorkers))}
                className="w-full p-3 border border-theme rounded-lg hover:bg-theme-warning-background hover:border-theme-warning text-left transition-colors"
              >
                <div className="flex items-center space-x-3">
                  <span className="text-xl">⏸️</span>
                  <div>
                    <div className="font-medium text-theme-primary">Suspend Workers</div>
                    <div className="text-sm text-theme-secondary">Temporarily disable access</div>
                  </div>
                </div>
              </button>
              
              <button
                onClick={() => handleBulkAction('activate', Array.from(state.selectedWorkers))}
                className="w-full p-3 border border-theme rounded-lg hover:bg-theme-success-background hover:border-theme-success text-left transition-colors"
              >
                <div className="flex items-center space-x-3">
                  <span className="text-xl">▶️</span>
                  <div>
                    <div className="font-medium text-theme-primary">Activate Workers</div>
                    <div className="text-sm text-theme-secondary">Enable access for suspended workers</div>
                  </div>
                </div>
              </button>
              
              <button
                onClick={() => handleBulkAction('delete', Array.from(state.selectedWorkers))}
                className="w-full p-3 border border-theme rounded-lg hover:bg-theme-error-background hover:border-theme-error text-left transition-colors"
              >
                <div className="flex items-center space-x-3">
                  <span className="text-xl">🗑️</span>
                  <div>
                    <div className="font-medium text-theme-primary">Delete Workers</div>
                    <div className="text-sm text-theme-secondary">Permanently remove workers</div>
                  </div>
                </div>
              </button>
            </div>
            
            <div className="flex justify-end">
              <button
                onClick={() => setState(prev => ({ ...prev, showBulkActionsModal: false }))}
                className="px-4 py-2 border border-theme rounded-lg text-theme-secondary hover:text-theme-primary transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
      
      {/* Export Modal */}
      {state.showExportModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-md border border-theme">
            <div className="mb-6">
              <h2 className="text-xl font-semibold text-theme-primary mb-2">Export Workers</h2>
              <p className="text-theme-secondary">
                {state.selectedWorkers.size > 0 
                  ? `Export ${state.selectedWorkers.size} selected worker(s)`
                  : `Export all ${filteredAndSortedWorkers.length} filtered worker(s)`
                }
              </p>
            </div>
            
            <div className="space-y-3 mb-6">
              <button
                onClick={() => handleExport('csv')}
                className="w-full p-3 border border-theme rounded-lg hover:bg-theme-background text-left transition-colors"
              >
                <div className="flex items-center space-x-3">
                  <span className="text-xl">📄</span>
                  <div>
                    <div className="font-medium text-theme-primary">Export as CSV</div>
                    <div className="text-sm text-theme-secondary">Comma-separated values for spreadsheets</div>
                  </div>
                </div>
              </button>
              
              <button
                onClick={() => handleExport('json')}
                className="w-full p-3 border border-theme rounded-lg hover:bg-theme-background text-left transition-colors"
              >
                <div className="flex items-center space-x-3">
                  <span className="text-xl">📜</span>
                  <div>
                    <div className="font-medium text-theme-primary">Export as JSON</div>
                    <div className="text-sm text-theme-secondary">Structured data for developers</div>
                  </div>
                </div>
              </button>
            </div>
            
            <div className="flex justify-end">
              <button
                onClick={() => setState(prev => ({ ...prev, showExportModal: false }))}
                className="px-4 py-2 border border-theme rounded-lg text-theme-secondary hover:text-theme-primary transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </PageContainer>
  );
};

export default WorkersPage;