import React, { useState, useEffect, useMemo } from 'react';
import { useSelector } from 'react-redux';

import { usersApi, User } from '@/features/account/users/services/usersApi';
import type { RootState } from '@/shared/services';

const PER_PAGE = 20;

// fc-38: migrated off adminSettingsApi.getUsers() (`/admin_settings/users`,
// deleted — no callers left it once this moved). usersApi.getAllUsers()
// (`/admin/users`) returns every user across every account in one response
// with no server-side pagination/status filter, so both are now applied
// client-side — which also FIXES the status filter: the old
// `/admin_settings/users` action silently ignored the `status` param it was
// sent, so this control has never actually filtered anything until now.
export const UserManagement: React.FC = () => {
  const [users, setUsers] = useState<User[]>([]);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const user = useSelector((state: RootState) => state.auth.user);

  useEffect(() => {
    loadUsers();
  }, []);

  const loadUsers = async () => {
    try {
      const response = await usersApi.getAllUsers();
      setUsers(response.data);
    } catch (_error) {
      // Error handling
    }
  };

  const filteredUsers = useMemo(
    () => (statusFilter ? users.filter((u) => u.status === statusFilter) : users),
    [users, statusFilter]
  );

  const totalPages = Math.max(1, Math.ceil(filteredUsers.length / PER_PAGE));
  const pagedUsers = filteredUsers.slice((currentPage - 1) * PER_PAGE, currentPage * PER_PAGE);

  const handleStatusFilter = (e: React.ChangeEvent<HTMLSelectElement>) => {
    setStatusFilter(e.target.value);
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
      {pagedUsers.map((userData) => (
        <div key={userData.id}>
          <div>{userData.email}</div>
          <div>{userData.name}</div>
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
      <span>Page {currentPage} of {totalPages}</span>
      <button
        onClick={() => setCurrentPage(prev => prev + 1)}
        disabled={currentPage >= totalPages}
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
