import React from 'react';
import { Filter, Search } from 'lucide-react';
import { UserFiltersPanelProps, StatusFilter, SortBy } from './types';

export const UserFiltersPanel: React.FC<UserFiltersPanelProps> = ({
  filters,
  totalUsers,
  filteredCount,
  onSearchChange,
  onStatusFilterChange,
  onSortByChange
}) => (
  <div className="bg-theme-surface rounded-xl p-6 shadow-sm mb-6">
    <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center">
      <Filter className="h-5 w-5 mr-2" />
      Advanced Filters
    </h3>

    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      {/* Search */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-2">Search</label>
        <div className="relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
          <input
            type="text"
            placeholder="Search users..."
            value={filters.searchTerm}
            onChange={(e) => onSearchChange(e.target.value)}
            className="input-theme pl-10"
          />
        </div>
      </div>

      {/* Status Filter */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-2">Status</label>
        <select
          value={filters.statusFilter}
          onChange={(e) => onStatusFilterChange(e.target.value as StatusFilter)}
          className="select-theme"
        >
          <option value="all">All Statuses</option>
          <option value="active">Active</option>
          <option value="suspended">Suspended</option>
          <option value="inactive">Inactive</option>
        </select>
      </div>

      {/* Sort Options */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-2">Sort By</label>
        <div className="flex gap-2">
          <select
            value={filters.sortBy}
            onChange={(e) => onSortByChange(e.target.value as SortBy)}
            className="select-theme w-full"
          >
            <option value="name">Name</option>
            <option value="email">Email</option>
            <option value="created_at">Created Date</option>
            <option value="last_login_at">Last Login</option>
          </select>
        </div>
      </div>
    </div>

    <div className="flex justify-center items-center mt-4">
      <span className="text-sm text-theme-secondary">
        Showing {filteredCount} of {totalUsers} users
      </span>
    </div>
  </div>
);
