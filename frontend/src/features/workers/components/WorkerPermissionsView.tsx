import React, { useState, useMemo } from 'react';
import { Worker } from '@/features/workers/services/workerApi';
import {
  Shield,
  Key,
  Search,
  ChevronDown,
  ChevronRight,
  Check
} from 'lucide-react';

export interface WorkerPermissionsViewProps {
  worker: Worker;
  isEditing: boolean;
  editedWorker?: Partial<Worker>;
  onWorkerChange?: (updates: Partial<Worker>) => void;
}

interface PermissionGroup {
  category: string;
  permissions: string[];
  description: string;
  color: string;
}

export const WorkerPermissionsView: React.FC<WorkerPermissionsViewProps> = ({
  worker,
  isEditing,
  editedWorker,
  onWorkerChange
}) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(new Set(['user', 'billing']));
  const [showAllPermissions, setShowAllPermissions] = useState(false);

  const currentWorker = editedWorker || worker;

  // Permission groups synced with backend permission categories
  const permissionGroups: PermissionGroup[] = useMemo(() => [
    {
      category: 'User & Team Management',
      permissions: ['user.read', 'user.edit_self', 'user.delete_self', 'team.read', 'team.invite', 'team.remove', 'team.assign_roles'],
      description: 'User profiles and team collaboration',
      color: 'bg-theme-info-background text-theme-info'
    },
    {
      category: 'Billing & Subscriptions',
      permissions: ['billing.read', 'billing.update', 'billing.cancel', 'plans.read', 'plans.create', 'plans.manage', 'invoice.read', 'invoice.download'],
      description: 'Subscription management and billing',
      color: 'bg-theme-warning-background text-theme-warning'
    },
    {
      category: 'Content & Pages',
      permissions: ['page.create', 'page.read', 'page.edit', 'page.delete', 'page.publish'],
      description: 'Content creation and management',
      color: 'bg-theme-success-background text-theme-success'
    },
    {
      category: 'Analytics & Reports',
      permissions: ['analytics.read', 'analytics.export', 'report.read', 'report.generate', 'report.export'],
      description: 'Data insights and reporting',
      color: 'bg-theme-surface text-theme-primary'
    },
    {
      category: 'API & Webhooks',
      permissions: ['api.read', 'api.write', 'api.manage_keys', 'webhook.read', 'webhook.create', 'webhook.edit', 'webhook.delete'],
      description: 'API access and webhook management',
      color: 'bg-theme-interactive-primary/10 text-theme-interactive-primary'
    },
    {
      category: 'Marketplace',
      permissions: ['app.read', 'app.create', 'app.edit', 'app.delete', 'app.publish', 'app.manage_features', 'app.manage_plans', 'listing.read', 'listing.create', 'subscription.read', 'subscription.create', 'review.read'],
      description: 'Marketplace apps and subscriptions',
      color: 'bg-theme-success-background/50 text-theme-success'
    },
    {
      category: 'Admin Operations',
      permissions: ['admin.access', 'admin.user.read', 'admin.user.create', 'admin.account.read', 'admin.billing.read', 'admin.settings.read', 'admin.audit.read'],
      description: 'Administrative functions and oversight',
      color: 'bg-theme-error-background text-theme-error'
    },
    {
      category: 'System & Workers',
      permissions: ['system.workers.read', 'system.workers.create', 'system.worker.register', 'system.jobs.process', 'system.health.check', 'system.database.read'],
      description: 'System operations and worker management',
      color: 'bg-theme-surface border border-theme text-theme-secondary'
    }
  ], []);

  // Get all available permissions from groups
  const allPermissions = useMemo(() => 
    permissionGroups.flatMap(group => group.permissions),
    [permissionGroups]
  );

  // Filter permissions based on search
  const filteredGroups = useMemo(() => {
    if (!searchTerm) return permissionGroups;

    return permissionGroups.map(group => ({
      ...group,
      permissions: group.permissions.filter(permission =>
        permission.toLowerCase().includes(searchTerm.toLowerCase()) ||
        group.category.toLowerCase().includes(searchTerm.toLowerCase())
      )
    })).filter(group => group.permissions.length > 0);
  }, [permissionGroups, searchTerm]);

  // Workers should not have custom permissions - only role-inherited permissions
  // If any exist, they should be migrated to proper roles

  const toggleCategory = (category: string) => {
    const newExpanded = new Set(expandedCategories);
    if (newExpanded.has(category)) {
      newExpanded.delete(category);
    } else {
      newExpanded.add(category);
    }
    setExpandedCategories(newExpanded);
  };

  // Permissions are read-only and inherited from roles
  // Direct permission editing is not allowed

  const handleRoleToggle = (role: string) => {
    if (!isEditing || !onWorkerChange) return;

    const currentRoles = currentWorker.roles || [];
    const newRoles = currentRoles.includes(role)
      ? currentRoles.filter(r => r !== role)
      : [...currentRoles, role];

    onWorkerChange({ roles: newRoles });
  };

  const getRoleDescription = (role: string): string => {
    const roleDescriptions: Record<string, string> = {
      'member': 'Basic account member with standard access',
      'manager': 'Team manager with content and team management capabilities',
      'billing_admin': 'Manages billing, subscriptions, and financial operations',
      'developer': 'App developer with marketplace publishing capabilities',
      'owner': 'Account owner with full account management capabilities',
      'admin': 'System administrator with full administrative access',
      'super_admin': 'Super administrator with full system access',
      'system_worker': 'Automated worker with system-level access',
      'task_worker': 'Worker limited to specific task execution'
    };
    return roleDescriptions[role] || 'Custom role with specific permissions';
  };

  const getRolePermissions = (role: string): string[] => {
    // Role-permission mappings synced with backend Permissions::ROLES
    const rolePermissionMap: Record<string, string[]> = {
      'member': [
        'user.read', 'user.edit_self', 'team.read', 'billing.read', 'page.read', 'analytics.read',
        'report.read', 'api.read', 'webhook.read', 'invoice.read', 'audit.read',
        'app.read', 'listing.read', 'subscription.read', 'subscription.create', 'subscription.manage',
        'subscription.cancel', 'subscription.read_usage', 'review.read'
      ],
      'manager': [
        'user.read', 'user.edit_self', 'team.read', 'team.invite', 'team.remove', 'team.assign_roles',
        'billing.read', 'billing.update', 'plans.read', 'plans.manage',
        'page.read', 'page.create', 'page.edit', 'page.delete', 'page.publish',
        'analytics.read', 'analytics.export', 'report.read', 'report.generate', 'report.export',
        'api.read', 'api.write', 'api.manage_keys', 'webhook.read', 'webhook.create', 'webhook.edit', 'webhook.delete',
        'invoice.read', 'invoice.download', 'audit.read', 'audit.export',
        'app.read', 'app.create', 'app.edit', 'app.delete', 'app.publish', 'app.manage_features', 'app.manage_plans', 'app.read_analytics',
        'listing.read', 'listing.create', 'listing.edit', 'listing.delete',
        'subscription.read', 'subscription.create', 'subscription.manage', 'subscription.cancel', 'subscription.upgrade', 'subscription.read_usage',
        'review.read', 'review.create', 'review.edit', 'review.delete', 'review.moderate'
      ],
      'billing_admin': [
        'user.read', 'user.edit_self', 'team.read', 'billing.read', 'billing.update', 'billing.cancel',
        'plans.read', 'plans.create', 'plans.manage', 'invoice.read', 'invoice.download',
        'analytics.read', 'report.read', 'report.generate', 'admin.billing.read', 'admin.billing.override',
        'admin.billing.refund', 'admin.billing.credit', 'audit.read'
      ],
      'developer': [
        'user.read', 'user.edit_self', 'team.read', 'billing.read', 'billing.update', 'plans.read',
        'page.read', 'analytics.read', 'analytics.export', 'report.read', 'report.generate',
        'api.read', 'api.write', 'api.manage_keys', 'webhook.read', 'webhook.create', 'webhook.edit',
        'invoice.read', 'invoice.download', 'audit.read',
        'app.read', 'app.create', 'app.edit', 'app.delete', 'app.publish', 'app.manage_features', 'app.manage_plans', 'app.read_analytics',
        'listing.read', 'listing.create', 'listing.edit', 'listing.delete',
        'subscription.read', 'subscription.create', 'subscription.manage', 'subscription.cancel', 'subscription.upgrade', 'subscription.read_usage',
        'review.read', 'review.create', 'review.edit', 'review.delete', 'review.moderate'
      ],
      'owner': [
        // All resource permissions + selected admin permissions
        ...allPermissions.filter(p => !p.startsWith('system.')), // All non-system permissions
        'admin.user.read', 'admin.user.create', 'admin.user.edit', 'admin.user.suspend',
        'admin.role.read', 'admin.role.assign', 'admin.billing.read', 'admin.billing.override',
        'admin.settings.read', 'admin.settings.edit', 'admin.audit.read', 'admin.audit.export'
      ],
      'admin': [
        // All resource permissions + most admin permissions (except maintenance)
        ...allPermissions.filter(p => !p.startsWith('system.') && !p.includes('maintenance'))
      ],
      'super_admin': [
        // All resource + admin + worker management permissions
        ...allPermissions.filter(p => !p.startsWith('system.') || p.startsWith('system.workers.'))
      ],
      'system_worker': [
        // All system permissions
        ...allPermissions.filter(p => p.startsWith('system.'))
      ],
      'task_worker': [
        'system.worker.register', 'system.worker.heartbeat', 'system.worker.report',
        'system.worker.execute', 'system.jobs.process', 'system.health.report', 'system.api.internal'
      ]
    };
    return rolePermissionMap[role] || [];
  };

  const getPermissionStatus = (permission: string): 'inherited' | 'none' => {
    // All permissions are inherited from roles, no direct permissions allowed
    const hasFromRole = (currentWorker.roles || []).some(role => 
      getRolePermissions(role).includes(permission)
    );
    return hasFromRole ? 'inherited' : 'none';
  };

  // Role definitions with types
  const roleTypes = {
    'member': 'user',
    'manager': 'user', 
    'billing_admin': 'user',
    'developer': 'user',
    'owner': 'user',
    'admin': 'admin',
    'super_admin': 'admin',
    'system_worker': 'system',
    'task_worker': 'system'
  };

  const isSystemWorker = worker.account_name === 'System';

  const getAvailableRolesForWorker = () => {
    const allRoles = ['member', 'manager', 'billing_admin', 'developer', 'owner', 'admin', 'super_admin', 'system_worker', 'task_worker'];
    
    if (isSystemWorker) {
      // System workers can have system and admin roles
      return allRoles.filter(role => ['system', 'admin'].includes(roleTypes[role as keyof typeof roleTypes]));
    } else {
      // Account workers can have specific user roles and task_worker
      return allRoles.filter(role => 
        (roleTypes[role as keyof typeof roleTypes] === 'user' && ['member', 'manager', 'billing_admin', 'developer', 'owner'].includes(role)) ||
        role === 'task_worker'
      );
    }
  };

  const getRoleTypeBadge = (roleType: string) => {
    switch (roleType) {
      case 'user':
        return { className: 'bg-theme-info-background text-theme-info', label: 'USER' };
      case 'admin':
        return { className: 'bg-theme-warning-background text-theme-warning', label: 'ADMIN' };
      case 'system':
        return { className: 'bg-theme-error-background text-theme-error', label: 'SYSTEM' };
      default:
        return { className: 'bg-theme-surface text-theme-secondary', label: 'UNKNOWN' };
    }
  };

  return (
    <div className="space-y-6">
      {/* Roles Section */}
      <div>
        <div className="flex items-center gap-2 mb-4">
          <Shield className="w-5 h-5 text-theme-primary" />
          <h3 className="text-lg font-semibold text-theme-primary">Roles</h3>
          <span className="text-sm text-theme-secondary">({(currentWorker.roles || []).length})</span>
        </div>

        {/* Role Type Information */}
        <div className="mb-4 p-3 bg-theme-info-background/30 border border-theme-info rounded-lg">
          <div className="text-sm text-theme-info">
            <strong>Role Restrictions:</strong> {isSystemWorker ? 'System workers' : 'Account workers'} can only be assigned 
            {isSystemWorker ? ' system and admin roles' : ' specific user roles and task worker role'} based on their worker type.
          </div>
        </div>

        <div className="space-y-3">
          {getAvailableRolesForWorker().map(role => {
            const isAssigned = (currentWorker.roles || []).includes(role);
            const inheritedPermissions = getRolePermissions(role);
            
            return (
              <div
                key={role}
                className={`p-4 rounded-lg border transition-colors ${
                  isAssigned 
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary/5' 
                    : 'border-theme bg-theme-surface'
                }`}
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-3">
                      {isEditing ? (
                        <input
                          type="checkbox"
                          checked={isAssigned}
                          onChange={() => handleRoleToggle(role)}
                          className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                        />
                      ) : (
                        <div className={`w-4 h-4 rounded border-2 flex items-center justify-center ${
                          isAssigned ? 'border-theme-interactive-primary bg-theme-interactive-primary' : 'border-theme'
                        }`}>
                          {isAssigned && <Check className="w-3 h-3 text-white" />}
                        </div>
                      )}
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-medium text-theme-primary">{role}</span>
                          {(() => {
                            const roleType = roleTypes[role as keyof typeof roleTypes];
                            const badge = getRoleTypeBadge(roleType);
                            return (
                              <span className={`text-xs px-2 py-0.5 rounded-full ${badge.className}`}>
                                {badge.label}
                              </span>
                            );
                          })()}
                        </div>
                        <div className="text-sm text-theme-secondary mt-1">
                          {getRoleDescription(role)}
                        </div>
                      </div>
                    </div>

                    {isAssigned && inheritedPermissions.length > 0 && (
                      <div className="mt-3 pl-7">
                        <div className="text-xs font-medium text-theme-secondary mb-2">
                          Inherited Permissions ({inheritedPermissions.length})
                        </div>
                        <div className="flex flex-wrap gap-1">
                          {inheritedPermissions.slice(0, showAllPermissions ? undefined : 5).map(permission => (
                            <span
                              key={permission}
                              className="px-2 py-1 bg-theme-background text-theme-secondary text-xs rounded-full font-mono"
                            >
                              {permission}
                            </span>
                          ))}
                          {!showAllPermissions && inheritedPermissions.length > 5 && (
                            <button
                              onClick={() => setShowAllPermissions(true)}
                              className="px-2 py-1 bg-theme-info-background text-theme-info text-xs rounded-full hover:bg-theme-info-background/80"
                            >
                              +{inheritedPermissions.length - 5} more
                            </button>
                          )}
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Permissions Section */}
      <div>
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <Key className="w-5 h-5 text-theme-primary" />
            <h3 className="text-lg font-semibold text-theme-primary">Inherited Permissions</h3>
            <span className="text-sm text-theme-secondary">
              (Read-only - inherited from {(currentWorker.roles || []).length} role{(currentWorker.roles || []).length !== 1 ? 's' : ''})
            </span>
          </div>

          {/* Search */}
          <div className="relative w-64">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-secondary w-4 h-4" />
            <input
              type="text"
              placeholder="Search permissions..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary text-sm"
            />
          </div>
        </div>

        {/* Permission Groups */}
        <div className="space-y-3">
          {filteredGroups.map(group => {
            const isExpanded = expandedCategories.has(group.category.toLowerCase());
            const groupPermissions = group.permissions;
            const inheritedCount = groupPermissions.filter(p => getPermissionStatus(p) === 'inherited').length;

            return (
              <div key={group.category} className="border border-theme rounded-lg bg-theme-surface">
                <button
                  onClick={() => toggleCategory(group.category.toLowerCase())}
                  className="w-full flex items-center justify-between p-4 text-left hover:bg-theme-background/50 transition-colors"
                >
                  <div className="flex items-center gap-3">
                    {isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                    <div>
                      <div className="font-medium text-theme-primary">{group.category}</div>
                      <div className="text-sm text-theme-secondary">{group.description}</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${group.color}`}>
                      {inheritedCount}/{groupPermissions.length} inherited
                    </span>
                  </div>
                </button>

                {isExpanded && (
                  <div className="px-4 pb-4 border-t border-theme">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-2 mt-3">
                      {groupPermissions.map(permission => {
                        const status = getPermissionStatus(permission);
                        
                        return (
                          <div
                            key={permission}
                            className={`flex items-center justify-between p-3 rounded-lg border transition-colors ${
                              status === 'inherited'
                                ? 'border-theme-success bg-theme-success-background'
                                : 'border-theme bg-theme-background opacity-50'
                            }`}
                          >
                            <div className="flex items-center gap-3 flex-1">
                              <div className={`w-4 h-4 rounded border-2 flex items-center justify-center ${
                                status === 'inherited'
                                  ? 'border-theme-success bg-theme-success'
                                  : 'border-theme'
                              }`}>
                                {status === 'inherited' && <Check className="w-3 h-3 text-white" />}
                              </div>
                              <div className="flex-1">
                                <div className="text-sm font-mono text-theme-primary">{permission}</div>
                                {status === 'inherited' && (
                                  <div className="text-xs text-theme-success">Inherited from assigned roles</div>
                                )}
                                {status === 'none' && (
                                  <div className="text-xs text-theme-secondary">Not granted by current roles</div>
                                )}
                              </div>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}
              </div>
            );
          })}

          {/* Information Box for Role-Based Permissions */}
          <div className="border border-theme-info rounded-lg bg-theme-info-background">
            <div className="flex items-start gap-3 p-4">
              <div className="p-1">
                <Shield className="w-5 h-5 text-theme-info" />
              </div>
              <div className="flex-1">
                <div className="font-medium text-theme-info mb-1">Role-Based Permission System</div>
                <div className="text-sm text-theme-info/80">
                  Workers inherit permissions from their assigned roles. To modify permissions, 
                  edit the worker's roles above. Direct permission assignment is not allowed for security reasons.
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Permission Summary */}
      <div className="bg-theme-background rounded-lg p-4">
        <h4 className="font-medium text-theme-primary mb-3">Permission Summary</h4>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-interactive-primary">{(currentWorker.roles || []).length}</div>
            <div className="text-theme-secondary">Assigned Roles</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-success">
              {new Set((currentWorker.roles || []).flatMap(role => getRolePermissions(role))).size}
            </div>
            <div className="text-theme-secondary">Total Permissions</div>
          </div>
        </div>
      </div>
    </div>
  );
};

