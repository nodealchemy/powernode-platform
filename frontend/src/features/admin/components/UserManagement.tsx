import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';

import { adminSettingsApi, AdminUser } from '../services/adminSettingsApi';
import type { RootState } from '@/shared/services';

export const UserManagement: React.FC = () => {
  const [usersData, setUsersData] = useState<{
    users: AdminUser[];
    pagination: {
      current_page: number;
      per_page: number;
      total_count: number;
      total_pages: number;
    };
  } | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const user = useSelector((state: RootState) => state.auth.user);

  useEffect(() => {
    loadUsers();
  }, [currentPage, statusFilter]);

  const loadUsers = async () => {
    try {
      const data = await adminSettingsApi.getUsers({
        page: currentPage,
        per_page: 20,
        status: statusFilter || undefined
      });
      setUsersData(data);
    } catch {
      // Error handling
    }
  };

  const handleStatusFilter = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const status = e.target.value;
    setStatusFilter(status);
    setCurrentPage(1); // Reset to first page on filter change
  };

  const hasPermission = (permission: string) => {
    return user?.permissions?.includes(permission);
  };

  return (
    <div>
      <h1>User Management</h1>

      {hasPermission('users.create') && (
        <button onClick={() => setShowCreateModal(true)}>Create User</button>
      )}

      <label htmlFor="status-filter">Filter by Status</label>
      <select id="status-filter" value={statusFilter} onChange={handleStatusFilter}>
        <option value="">All</option>
        <option value="active">Active</option>
        <option value="inactive">Inactive</option>
      </select>

      {/* Users List */}
      {usersData?.users.map((userData: AdminUser) => (
        <div key={userData.id}>
          <div>{userData.email}</div>
          <div>{userData.full_name || userData.name}</div>
          <div>{userData.account.status === 'active' ? 'Active' : 'Suspended'}</div>
          {userData.roles?.map((role: string) => (
            <span key={role}>{role}</span>
          ))}
        </div>
      ))}

      {/* Pagination */}
      <button
        onClick={() => setCurrentPage(prev => Math.max(1, prev - 1))}
        disabled={currentPage <= 1}
      >
        Previous
      </button>
      <span>Page {currentPage} of {usersData?.pagination.total_pages || 1}</span>
      <button
        onClick={() => setCurrentPage(prev => prev + 1)}
        disabled={!usersData || currentPage >= usersData.pagination.total_pages}
      >
        Next
      </button>

      {/* Create Modal */}
      {showCreateModal && (
        <div>
          <h2>Create New User</h2>
          <label htmlFor="email">Email</label>
          <input id="email" type="email" />
          <label htmlFor="first-name">First Name</label>
          <input id="first-name" />
          <label htmlFor="last-name">Last Name</label>
          <input id="last-name" />
          <button>Create</button>
        </div>
      )}
    </div>
  );
};
