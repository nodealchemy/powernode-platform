import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { TabNavigation, MobileTabNavigation } from '../../components/ui/TabNavigation';
import { Breadcrumb } from '../../components/ui/Breadcrumb';
import UsersPage from './UsersPage';
import AccountsPage from './AccountsPage';

const tabs = [
  { id: 'users', label: 'Users', path: '/dashboard/users/all', icon: '👤' },
  { id: 'accounts', label: 'Accounts', path: '/dashboard/users/accounts', icon: '🏢' },
  { id: 'roles', label: 'Roles', path: '/dashboard/users/roles', icon: '🔐' },
  { id: 'permissions', label: 'Permissions', path: '/dashboard/users/permissions', icon: '🛡️' },
  { id: 'invitations', label: 'Invitations', path: '/dashboard/users/invitations', icon: '✉️' },
  { id: 'delegations', label: 'Delegations', path: '/dashboard/users/delegations', icon: '🤝' },
];

const RolesPage: React.FC = () => {
  const systemRoles = [
    { name: 'Owner', users: 1, permissions: 'All permissions', system: true, color: 'purple' },
    { name: 'Admin', users: 2, permissions: 'Full access except ownership', system: true, color: 'blue' },
    { name: 'Manager', users: 3, permissions: 'User & content management', system: true, color: 'green' },
    { name: 'Support', users: 5, permissions: 'Customer support access', system: true, color: 'yellow' },
    { name: 'Viewer', users: 8, permissions: 'Read-only access', system: true, color: 'gray' },
  ];

  const customRoles = [
    { name: 'Finance Manager', users: 1, permissions: 'Billing & invoicing', system: false, color: 'indigo' },
    { name: 'Content Editor', users: 2, permissions: 'Content creation & editing', system: false, color: 'pink' },
  ];

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Role Management</h2>
            <p className="text-theme-secondary mt-1">Define roles and their associated permissions</p>
          </div>
          <button className="btn-theme btn-theme-primary">
            Create Role
          </button>
        </div>

        <div className="mb-8">
          <h3 className="text-lg font-medium text-theme-primary mb-4">System Roles</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {systemRoles.map((role) => (
              <div key={role.name} className="bg-theme-background rounded-lg p-4 border border-theme">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center space-x-2">
                    <div className={`w-2 h-2 bg-${role.color}-500 rounded-full`} />
                    <h4 className="font-medium text-theme-primary">{role.name}</h4>
                  </div>
                  <span className="text-xs bg-theme-surface px-2 py-1 rounded text-theme-tertiary">
                    System
                  </span>
                </div>
                <p className="text-sm text-theme-secondary mb-2">{role.permissions}</p>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">{role.users} users</span>
                  <button className="text-theme-link hover:text-theme-link-hover">
                    View Details
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div>
          <h3 className="text-lg font-medium text-theme-primary mb-4">Custom Roles</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {customRoles.map((role) => (
              <div key={role.name} className="bg-theme-background rounded-lg p-4 border border-theme">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center space-x-2">
                    <div className={`w-2 h-2 bg-${role.color}-500 rounded-full`} />
                    <h4 className="font-medium text-theme-primary">{role.name}</h4>
                  </div>
                  <span className="text-xs bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary px-2 py-1 rounded">
                    Custom
                  </span>
                </div>
                <p className="text-sm text-theme-secondary mb-2">{role.permissions}</p>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">{role.users} users</span>
                  <div className="flex space-x-2">
                    <button className="text-theme-link hover:text-theme-link-hover">
                      Edit
                    </button>
                    <button className="text-theme-error hover:text-theme-error-hover">
                      Delete
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

const PermissionsPage: React.FC = () => {
  const permissionGroups = [
    {
      name: 'Users',
      permissions: [
        { name: 'user_view', label: 'View Users', description: 'Can view user profiles and lists' },
        { name: 'user_create', label: 'Create Users', description: 'Can create new user accounts' },
        { name: 'user_edit', label: 'Edit Users', description: 'Can modify user information' },
        { name: 'user_delete', label: 'Delete Users', description: 'Can remove user accounts' },
      ]
    },
    {
      name: 'Billing & Subscriptions',
      permissions: [
        { name: 'billing_view', label: 'View Billing', description: 'Can view billing information' },
        { name: 'billing_manage', label: 'Manage Billing', description: 'Can process payments and refunds' },
        { name: 'subscription_manage', label: 'Manage Subscriptions', description: 'Can modify subscription plans' },
        { name: 'invoice_create', label: 'Create Invoices', description: 'Can generate and send invoices' },
      ]
    },
    {
      name: 'System Administration',
      permissions: [
        { name: 'settings_view', label: 'View Settings', description: 'Can view system settings' },
        { name: 'settings_manage', label: 'Manage Settings', description: 'Can modify system configuration' },
        { name: 'audit_view', label: 'View Audit Logs', description: 'Can access system audit trails' },
        { name: 'api_manage', label: 'Manage API Keys', description: 'Can create and revoke API keys' },
      ]
    },
  ];

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="mb-6">
          <h2 className="text-xl font-semibold text-theme-primary">Permission Management</h2>
          <p className="text-theme-secondary mt-1">Configure granular permissions for roles and users</p>
        </div>

        {permissionGroups.map((group) => (
          <div key={group.name} className="mb-8">
            <h3 className="text-lg font-medium text-theme-primary mb-4">{group.name}</h3>
            <div className="bg-theme-background rounded-lg overflow-hidden">
              <table className="w-full">
                <thead className="bg-theme-surface border-b border-theme">
                  <tr>
                    <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Permission</th>
                    <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Description</th>
                    <th className="text-center py-3 px-4 text-sm font-medium text-theme-primary">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-theme">
                  {group.permissions.map((permission) => (
                    <tr key={permission.name} className="hover:bg-theme-surface-hover">
                      <td className="py-3 px-4">
                        <div>
                          <p className="font-medium text-theme-primary">{permission.label}</p>
                          <p className="text-xs text-theme-tertiary font-mono">{permission.name}</p>
                        </div>
                      </td>
                      <td className="py-3 px-4 text-sm text-theme-secondary">
                        {permission.description}
                      </td>
                      <td className="py-3 px-4 text-center">
                        <label className="relative inline-flex items-center cursor-pointer">
                          <input type="checkbox" className="sr-only peer" defaultChecked />
                          <div className="w-11 h-6 bg-theme-surface rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
                        </label>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

const InvitationsPage: React.FC = () => {
  const pendingInvitations = [
    { email: 'john.doe@example.com', role: 'Manager', invitedBy: 'Admin User', sentAt: '2024-03-10', status: 'pending' },
    { email: 'jane.smith@example.com', role: 'Support', invitedBy: 'Admin User', sentAt: '2024-03-09', status: 'pending' },
  ];

  const acceptedInvitations = [
    { email: 'mike.wilson@example.com', role: 'Admin', invitedBy: 'Owner', sentAt: '2024-03-05', acceptedAt: '2024-03-06' },
    { email: 'sarah.jones@example.com', role: 'Viewer', invitedBy: 'Manager', sentAt: '2024-03-01', acceptedAt: '2024-03-01' },
  ];

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">User Invitations</h2>
            <p className="text-theme-secondary mt-1">Manage invitations sent to new users</p>
          </div>
          <button className="btn-theme btn-theme-primary">
            Send Invitation
          </button>
        </div>

        <div className="mb-8">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Pending Invitations</h3>
          <div className="bg-theme-background rounded-lg overflow-hidden">
            <table className="w-full">
              <thead className="bg-theme-surface border-b border-theme">
                <tr>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Email</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Role</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Invited By</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Sent</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {pendingInvitations.map((invitation) => (
                  <tr key={invitation.email} className="hover:bg-theme-surface-hover">
                    <td className="py-3 px-4 text-theme-primary">{invitation.email}</td>
                    <td className="py-3 px-4">
                      <span className="text-sm bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary px-2 py-1 rounded">
                        {invitation.role}
                      </span>
                    </td>
                    <td className="py-3 px-4 text-theme-secondary">{invitation.invitedBy}</td>
                    <td className="py-3 px-4 text-theme-secondary">{invitation.sentAt}</td>
                    <td className="py-3 px-4">
                      <div className="flex space-x-2">
                        <button className="text-theme-link hover:text-theme-link-hover text-sm">
                          Resend
                        </button>
                        <button className="text-theme-error hover:text-theme-error-hover text-sm">
                          Cancel
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <h3 className="text-lg font-medium text-theme-primary mb-4">Accepted Invitations</h3>
          <div className="bg-theme-background rounded-lg overflow-hidden">
            <table className="w-full">
              <thead className="bg-theme-surface border-b border-theme">
                <tr>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Email</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Role</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Invited By</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Accepted</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {acceptedInvitations.map((invitation) => (
                  <tr key={invitation.email} className="hover:bg-theme-surface-hover">
                    <td className="py-3 px-4 text-theme-primary">{invitation.email}</td>
                    <td className="py-3 px-4">
                      <span className="text-sm bg-green-100 text-green-700 px-2 py-1 rounded">
                        {invitation.role}
                      </span>
                    </td>
                    <td className="py-3 px-4 text-theme-secondary">{invitation.invitedBy}</td>
                    <td className="py-3 px-4 text-theme-secondary">{invitation.acceptedAt}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
};

const DelegationsPage: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Account Delegations</h2>
            <p className="text-theme-secondary mt-1">Manage cross-account access and delegations</p>
          </div>
          <button className="btn-theme btn-theme-primary">
            Create Delegation
          </button>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Active Delegations</h3>
            <div className="space-y-3">
              <div className="bg-theme-background rounded-lg p-4 border border-theme">
                <div className="flex items-center justify-between mb-2">
                  <h4 className="font-medium text-theme-primary">Support Team Access</h4>
                  <span className="text-xs bg-green-100 text-green-700 px-2 py-1 rounded">Active</span>
                </div>
                <p className="text-sm text-theme-secondary mb-3">
                  Allows support team to access customer data for assistance
                </p>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">3 users</span>
                  <button className="text-theme-link hover:text-theme-link-hover">
                    Manage
                  </button>
                </div>
              </div>
              
              <div className="bg-theme-background rounded-lg p-4 border border-theme">
                <div className="flex items-center justify-between mb-2">
                  <h4 className="font-medium text-theme-primary">Finance Department</h4>
                  <span className="text-xs bg-green-100 text-green-700 px-2 py-1 rounded">Active</span>
                </div>
                <p className="text-sm text-theme-secondary mb-3">
                  Access to billing and invoice management
                </p>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-tertiary">2 users</span>
                  <button className="text-theme-link hover:text-theme-link-hover">
                    Manage
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Delegation Requests</h3>
            <div className="bg-theme-background rounded-lg p-8 text-center border border-theme">
              <span className="text-4xl">🤝</span>
              <p className="text-theme-secondary mt-2">No pending delegation requests</p>
              <p className="text-theme-tertiary text-sm mt-1">
                Delegation requests will appear here for approval
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export const UserManagementPage: React.FC = () => {
  const breadcrumbItems = [
    { label: 'Dashboard', path: '/dashboard', icon: '🏠' },
    { label: 'Users', icon: '👥' }
  ];

  return (
    <div className="space-y-6">
      <div>
        <Breadcrumb items={breadcrumbItems} className="mb-4" />
        <h1 className="text-2xl font-bold text-theme-primary">Users</h1>
        <p className="text-theme-secondary mt-1">
          Manage users, accounts, roles, permissions, and access control.
        </p>
      </div>

      <div>
        <div className="hidden sm:block">
          <TabNavigation tabs={tabs} basePath="/dashboard/users" />
        </div>
        <MobileTabNavigation tabs={tabs} basePath="/dashboard/users" />
      </div>

      <div>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard/users/all" replace />} />
          <Route path="/all" element={<UsersPage />} />
          <Route path="/accounts" element={<AccountsPage />} />
          <Route path="/roles" element={<RolesPage />} />
          <Route path="/permissions" element={<PermissionsPage />} />
          <Route path="/invitations" element={<InvitationsPage />} />
          <Route path="/delegations" element={<DelegationsPage />} />
        </Routes>
      </div>
    </div>
  );
};

export default UserManagementPage;