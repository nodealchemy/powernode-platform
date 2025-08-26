import React, { useState } from 'react';
import { WorkerFiltersState } from '@/pages/app/system/WorkersPage';
import { Search, Filter, X, ChevronDown } from 'lucide-react';

export interface WorkerFiltersProps {
  filters: WorkerFiltersState;
  onChange: (filters: Partial<WorkerFiltersState>) => void;
  totalWorkers: number;
  filteredWorkers: number;
}

const availableRoles = [
  { value: 'member', label: 'Member' },
  { value: 'developer', label: 'App Developer' },
  { value: 'billing_admin', label: 'Billing Administrator' },
  { value: 'admin', label: 'Administrator' },
  { value: 'super_admin', label: 'Super Administrator' },
  { value: 'system_worker', label: 'System Worker' },
  { value: 'task_worker', label: 'Task Worker' }
];

const commonPermissions = [
  'admin.access',
  'system.workers.view',
  'system.workers.create',
  'system.workers.edit',
  'system.workers.delete',
  'api.read',
  'api.write',
  'billing.manage',
  'user.manage'
];

export const WorkerFilters: React.FC<WorkerFiltersProps> = ({
  filters,
  onChange,
  totalWorkers,
  filteredWorkers
}) => {
  const [showAdvanced, setShowAdvanced] = useState(false);

  const hasActiveFilters = filters.search !== '' || 
    filters.status !== 'all' || 
    filters.roleType !== 'all' || 
    filters.roles.length > 0 || 
    filters.permissions.length > 0;

  const clearAllFilters = () => {
    onChange({
      search: '',
      status: 'all',
      roleType: 'all',
      roles: [],
      permissions: [],
      sortBy: 'created_at',
      sortOrder: 'desc'
    });
    setShowAdvanced(false);
  };

  const toggleRole = (role: string) => {
    const newRoles = filters.roles.includes(role)
      ? filters.roles.filter(r => r !== role)
      : [...filters.roles, role];
    onChange({ roles: newRoles });
  };

  const togglePermission = (permission: string) => {
    const newPermissions = filters.permissions.includes(permission)
      ? filters.permissions.filter(p => p !== permission)
      : [...filters.permissions, permission];
    onChange({ permissions: newPermissions });
  };

  return (
    <div className="space-y-4">
      {/* Primary Filters */}
      <div className="flex flex-col lg:flex-row gap-4">
        {/* Search */}
        <div className="flex-1 relative">
          <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            <Search className="h-4 w-4 text-theme-secondary" />
          </div>
          <input
            type="text"
            placeholder="Search workers, tokens, permissions..."
            value={filters.search}
            onChange={(e) => onChange({ search: e.target.value })}
            className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
          />
          {filters.search && (
            <button
              onClick={() => onChange({ search: '' })}
              className="absolute inset-y-0 right-0 pr-3 flex items-center text-theme-secondary hover:text-theme-primary"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>

        {/* Quick Filters */}
        <div className="flex gap-2">
          {/* Status Filter */}
          <select
            value={filters.status}
            onChange={(e) => onChange({ status: e.target.value as any })}
            className="px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
          >
            <option value="all">📊 All Status</option>
            <option value="active">✅ Active</option>
            <option value="suspended">⏸️ Suspended</option>
            <option value="revoked">❌ Revoked</option>
          </select>

          {/* Role Type Filter */}
          <select
            value={filters.roleType}
            onChange={(e) => onChange({ roleType: e.target.value as any })}
            className="px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
          >
            <option value="all">🔄 All Types</option>
            <option value="system">⚙️ System</option>
            <option value="account">👥 Account</option>
          </select>

          {/* Advanced Filters Toggle */}
          <button
            onClick={() => setShowAdvanced(!showAdvanced)}
            className={`px-3 py-2 border border-theme rounded-lg transition-colors flex items-center gap-2 ${
              showAdvanced || hasActiveFilters
                ? 'bg-theme-interactive-primary text-white'
                : 'bg-theme-background text-theme-primary hover:bg-theme-surface'
            }`}
          >
            <Filter className="h-4 w-4" />
            <span>Filters</span>
            <ChevronDown className={`h-4 w-4 transition-transform ${showAdvanced ? 'rotate-180' : ''}`} />
          </button>
        </div>
      </div>

      {/* Results Counter */}
      <div className="flex items-center justify-between">
        <div className="text-sm text-theme-secondary">
          {filteredWorkers === totalWorkers ? (
            <span>Showing all {totalWorkers} workers</span>
          ) : (
            <span>Showing {filteredWorkers} of {totalWorkers} workers</span>
          )}
        </div>

        {hasActiveFilters && (
          <button
            onClick={clearAllFilters}
            className="text-sm text-theme-interactive-primary hover:text-theme-interactive-primary/80 flex items-center gap-1"
          >
            <X className="h-3 w-3" />
            Clear all filters
          </button>
        )}
      </div>

      {/* Advanced Filters */}
      {showAdvanced && (
        <div className="border border-theme rounded-lg p-4 bg-theme-surface space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Roles Filter */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Filter by Roles ({filters.roles.length} selected)
              </label>
              <div className="space-y-2 max-h-32 overflow-y-auto border border-theme rounded p-2 bg-theme-background">
                {availableRoles.map((role) => (
                  <label key={role.value} className="flex items-center space-x-2 text-sm">
                    <input
                      type="checkbox"
                      checked={filters.roles.includes(role.value)}
                      onChange={() => toggleRole(role.value)}
                      className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                    />
                    <span className="text-theme-primary">{role.label}</span>
                  </label>
                ))}
              </div>
            </div>

            {/* Permissions Filter */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Filter by Permissions ({filters.permissions.length} selected)
              </label>
              <div className="space-y-2 max-h-32 overflow-y-auto border border-theme rounded p-2 bg-theme-background">
                {commonPermissions.map((permission) => (
                  <label key={permission} className="flex items-center space-x-2 text-sm">
                    <input
                      type="checkbox"
                      checked={filters.permissions.includes(permission)}
                      onChange={() => togglePermission(permission)}
                      className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                    />
                    <span className="text-theme-primary font-mono text-xs">{permission}</span>
                  </label>
                ))}
              </div>
            </div>
          </div>

          {/* Sort Options */}
          <div className="flex items-center gap-4 pt-4 border-t border-theme">
            <label className="text-sm font-medium text-theme-primary">Sort by:</label>
            <select
              value={filters.sortBy}
              onChange={(e) => onChange({ sortBy: e.target.value as any })}
              className="px-3 py-1 border border-theme rounded bg-theme-background text-theme-primary text-sm"
            >
              <option value="name">Name</option>
              <option value="created_at">Created Date</option>
              <option value="last_seen_at">Last Activity</option>
              <option value="request_count">Request Count</option>
            </select>
            <select
              value={filters.sortOrder}
              onChange={(e) => onChange({ sortOrder: e.target.value as any })}
              className="px-3 py-1 border border-theme rounded bg-theme-background text-theme-primary text-sm"
            >
              <option value="asc">Ascending</option>
              <option value="desc">Descending</option>
            </select>
          </div>
        </div>
      )}

      {/* Active Filters Display */}
      {hasActiveFilters && (
        <div className="flex flex-wrap gap-2">
          {filters.search && (
            <div className="flex items-center gap-1 px-2 py-1 bg-theme-interactive-primary/10 text-theme-interactive-primary text-sm rounded">
              <Search className="h-3 w-3" />
              <span>"{filters.search}"</span>
              <button onClick={() => onChange({ search: '' })}>
                <X className="h-3 w-3" />
              </button>
            </div>
          )}
          {filters.status !== 'all' && (
            <div className="flex items-center gap-1 px-2 py-1 bg-theme-interactive-primary/10 text-theme-interactive-primary text-sm rounded">
              <span>Status: {filters.status}</span>
              <button onClick={() => onChange({ status: 'all' })}>
                <X className="h-3 w-3" />
              </button>
            </div>
          )}
          {filters.roleType !== 'all' && (
            <div className="flex items-center gap-1 px-2 py-1 bg-theme-interactive-primary/10 text-theme-interactive-primary text-sm rounded">
              <span>Type: {filters.roleType}</span>
              <button onClick={() => onChange({ roleType: 'all' })}>
                <X className="h-3 w-3" />
              </button>
            </div>
          )}
          {filters.roles.map((role) => (
            <div key={role} className="flex items-center gap-1 px-2 py-1 bg-theme-interactive-primary/10 text-theme-interactive-primary text-sm rounded">
              <span>Role: {availableRoles.find(r => r.value === role)?.label || role}</span>
              <button onClick={() => toggleRole(role)}>
                <X className="h-3 w-3" />
              </button>
            </div>
          ))}
          {filters.permissions.map((permission) => (
            <div key={permission} className="flex items-center gap-1 px-2 py-1 bg-theme-interactive-primary/10 text-theme-interactive-primary text-sm rounded">
              <span className="font-mono text-xs">Perm: {permission}</span>
              <button onClick={() => togglePermission(permission)}>
                <X className="h-3 w-3" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default WorkerFilters;