import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { adminApi } from '../services/adminApi';

const UserManagement: React.FC = () => {
  const [usersData, setUsersData] = useState<{
    users: any[];
    total_count: number;
    active_count: number;
    inactive_count: number;
    suspended_count: number;
  } | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const user = useSelector((state: any) => state.auth.user);

  useEffect(() => {
    loadUsers();
  }, [currentPage]);

  const loadUsers = async (statusFilter?: string) => {
    try {
      const data = await adminApi.getUsers(statusFilter ? { status: statusFilter } : undefined);
      setUsersData(data);
    } catch (error) {
      console.error('Failed to load users', error);
    }
  };

  const handleStatusFilter = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const status = e.target.value;
    if (status) {
      loadUsers(status);
    }
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
      <select id="status-filter" onChange={handleStatusFilter}>
        <option value="">All</option>
        <option value="active">Active</option>
        <option value="inactive">Inactive</option>
      </select>

      {/* Users List */}
      {usersData?.users.map((user: any) => (
        <div key={user.id}>
          <div>{user.email}</div>
          <div>{user.first_name} {user.last_name}</div>
          <div>{user.status === 'active' ? 'Active' : 'Suspended'}</div>
          {user.roles?.map((role: string) => (
            <span key={role}>{role}</span>
          ))}
        </div>
      ))}

      {/* Pagination */}
      <button onClick={() => setCurrentPage(prev => Math.max(1, prev - 1))}>Previous</button>
      <button onClick={() => setCurrentPage(prev => prev + 1)}>Next</button>

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

export default UserManagement;