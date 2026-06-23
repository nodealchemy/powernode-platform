import React, { useState, useMemo, useEffect } from 'react';
import { Worker } from '@/features/admin/workers/services/workerApi';
import { rolesApi, Role, Permission } from '@/features/admin/roles/services/rolesApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { getErrorMessage } from '@/shared/services/errorHandler';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
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
  // Stable grouping key (the permission `resource`, e.g. "user", "admin.billing").
  resource: string;
  category: string;
  permissions: string[];
  description: string;
  color: string;
}

// UI-only styling/labels keyed by the permission `resource` (the dotted prefix the
// catalog already returns). This map contains NO permission strings — it is purely
// presentation. Resources not listed here fall back to a humanized label + neutral
// styling, so extension-contributed resources render correctly without being named.
interface ResourceStyle {
  category: string;
  description: string;
  color: string;
}

const RESOURCE_STYLES: Record<string, ResourceStyle> = {
  user: {
    category: 'User & Team Management',
    description: 'User profiles and team collaboration',
    color: 'bg-theme-info-bg text-theme-info-fg'
  },
  team: {
    category: 'User & Team Management',
    description: 'User profiles and team collaboration',
    color: 'bg-theme-info-bg text-theme-info-fg'
  },
  billing: {
    category: 'Billing & Subscriptions',
    description: 'Subscription management and billing',
    color: 'bg-theme-warning-bg text-theme-warning-fg'
  },
  page: {
    category: 'Content & Pages',
    description: 'Content creation and management',
    color: 'bg-theme-success-bg text-theme-success-fg'
  },
  analytics: {
    category: 'Analytics & Reports',
    description: 'Data insights and reporting',
    color: 'bg-theme-surface text-theme-primary'
  },
  report: {
    category: 'Analytics & Reports',
    description: 'Data insights and reporting',
    color: 'bg-theme-surface text-theme-primary'
  },
  api: {
    category: 'API & Webhooks',
    description: 'API access and webhook management',
    color: 'bg-theme-interactive-primary/10 text-theme-interactive-primary'
  },
  webhook: {
    category: 'API & Webhooks',
    description: 'API access and webhook management',
    color: 'bg-theme-interactive-primary/10 text-theme-interactive-primary'
  },
  admin: {
    category: 'Admin Operations',
    description: 'Administrative functions and oversight',
    color: 'bg-theme-error-bg text-theme-error-fg'
  },
  system: {
    category: 'System & Workers',
    description: 'System operations and worker management',
    color: 'bg-theme-surface border border-theme text-theme-secondary'
  }
};

const DEFAULT_RESOURCE_STYLE: ResourceStyle = {
  category: '',
  description: 'Permissions for this resource',
  color: 'bg-theme-surface border border-theme text-theme-secondary'
};

// Humanize a dotted resource key (e.g. "admin.billing" -> "Admin Billing") for
// resources that do not have an explicit friendly category label.
const humanizeResource = (resource: string): string =>
  resource
    .split('.')
    .map(part => part.replace(/_/g, ' '))
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');

const styleForResource = (resource: string): ResourceStyle => {
  // Match on the leading segment so e.g. "admin.billing" inherits "admin" styling.
  const head = resource.split('.')[0];
  const style = RESOURCE_STYLES[resource] || RESOURCE_STYLES[head];
  if (style) return style;
  return { ...DEFAULT_RESOURCE_STYLE, category: humanizeResource(resource) };
};

export const WorkerPermissionsView: React.FC<WorkerPermissionsViewProps> = ({
  worker,
  isEditing,
  editedWorker,
  onWorkerChange
}) => {
  const { showNotification } = useNotifications();
  const [searchTerm, setSearchTerm] = useState('');
  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(new Set(['user', 'billing']));
  const [showAllPermissions, setShowAllPermissions] = useState(false);

  // Catalog-derived data (source of truth = backend permission catalog + roles).
  const [permissions, setPermissions] = useState<Permission[]>([]);
  const [roles, setRoles] = useState<Role[]>([]);
  const [loading, setLoading] = useState(true);

  const currentWorker = editedWorker || worker;

  const showNotificationRef = React.useRef(showNotification);
  useEffect(() => {
    showNotificationRef.current = showNotification;
  }, [showNotification]);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        setLoading(true);
        const [permissionsResponse, rolesResponse] = await Promise.all([
          rolesApi.getPermissions(),
          rolesApi.getRoles()
        ]);
        if (cancelled) return;
        setPermissions(permissionsResponse.data || []);
        setRoles(rolesResponse.data || []);
      } catch (error: unknown) {
        if (cancelled) return;
        showNotificationRef.current(`Failed to load permissions: ${getErrorMessage(error)}`, 'error');
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    load();
    return () => {
      cancelled = true;
    };
  }, []);

  // Group catalog permissions by their `resource`, then collapse resources that share
  // a friendly category (e.g. user + team) into a single display group.
  const permissionGroups: PermissionGroup[] = useMemo(() => {
    const byCategory = new Map<string, PermissionGroup>();
    permissions.forEach(permission => {
      const style = styleForResource(permission.resource);
      const category = style.category || humanizeResource(permission.resource);
      const existing = byCategory.get(category);
      if (existing) {
        existing.permissions.push(permission.name);
      } else {
        byCategory.set(category, {
          resource: permission.resource,
          category,
          description: style.description,
          color: style.color,
          permissions: [permission.name]
        });
      }
    });
    return Array.from(byCategory.values()).sort((a, b) => a.category.localeCompare(b.category));
  }, [permissions]);

  // Map of role name -> permission names, derived from the roles API.
  const rolePermissionMap = useMemo(() => {
    const map: Record<string, string[]> = {};
    roles.forEach(role => {
      map[role.name] = role.permissions.map(p => p.name);
    });
    return map;
  }, [roles]);

  const getRolePermissions = (role: string): string[] => rolePermissionMap[role] || [];

  const getRoleDescription = (role: string): string => {
    const match = roles.find(r => r.name === role);
    return match?.description || 'Custom role with specific permissions';
  };

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

  const getPermissionStatus = (permission: string): 'inherited' | 'none' => {
    // All permissions are inherited from roles, no direct permissions allowed
    const hasFromRole = (currentWorker.roles || []).some(role =>
      getRolePermissions(role).includes(permission)
    );
    return hasFromRole ? 'inherited' : 'none';
  };

  const isSystemWorker = worker.account_name === 'System';

  // Role classification comes straight from the backend catalog (role_type:
  // user | admin | system) — the authoritative taxonomy. Account workers hold
  // user-type roles; System workers hold admin/system-type roles. Mirrors the
  // catalog rule "role_type: user => assignable to per-account workers" and
  // Worker.assignable_roles_for_account.
  const getRoleType = (role: Role): 'system' | 'admin' | 'user' => role.role_type;

  const availableRoles = useMemo(() => {
    if (isSystemWorker) {
      // System workers can hold system and admin (global) roles.
      return roles.filter(role => getRoleType(role) !== 'user');
    }
    // Account workers can hold account-scoped / user roles.
    return roles.filter(role => getRoleType(role) === 'user');
  }, [roles, isSystemWorker]);

  const getRoleTypeBadge = (roleType: string) => {
    switch (roleType) {
      case 'user':
        return { className: 'bg-theme-info-bg text-theme-info-fg', label: 'USER' };
      case 'admin':
        return { className: 'bg-theme-warning-bg text-theme-warning-fg', label: 'ADMIN' };
      case 'system':
        return { className: 'bg-theme-error-bg text-theme-error-fg', label: 'SYSTEM' };
      default:
        return { className: 'bg-theme-surface text-theme-secondary', label: 'UNKNOWN' };
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center h-64">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

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
        <div className="mb-4 p-3 bg-theme-info-fg/30 border border-theme-info-border rounded-lg">
          <div className="text-sm text-theme-info-fg">
            <strong>Role Restrictions:</strong> {isSystemWorker ? 'System workers' : 'Account workers'} can only be assigned
            {isSystemWorker ? ' system and admin roles' : ' specific user roles and task worker role'} based on their worker type.
          </div>
        </div>

        <div className="space-y-3">
          {availableRoles.map(roleObj => {
            const role = roleObj.name;
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
                            const badge = getRoleTypeBadge(getRoleType(roleObj));
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
                              className="px-2 py-1 bg-theme-info-bg text-theme-info-fg text-xs rounded-full hover:bg-theme-info-fg/80"
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
                                ? 'border-theme-success-border bg-theme-success-bg'
                                : 'border-theme bg-theme-background opacity-50'
                            }`}
                          >
                            <div className="flex items-center gap-3 flex-1">
                              <div className={`w-4 h-4 rounded border-2 flex items-center justify-center ${
                                status === 'inherited'
                                  ? 'border-theme-success-border bg-theme-success-bg'
                                  : 'border-theme'
                              }`}>
                                {status === 'inherited' && <Check className="w-3 h-3 text-white" />}
                              </div>
                              <div className="flex-1">
                                <div className="text-sm font-mono text-theme-primary">{permission}</div>
                                {status === 'inherited' && (
                                  <div className="text-xs text-theme-success-fg">Inherited from assigned roles</div>
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
          <div className="border border-theme-info-border rounded-lg bg-theme-info-bg">
            <div className="flex items-start gap-3 p-4">
              <div className="p-1">
                <Shield className="w-5 h-5 text-theme-info-fg" />
              </div>
              <div className="flex-1">
                <div className="font-medium text-theme-info-fg mb-1">Role-Based Permission System</div>
                <div className="text-sm text-theme-info-fg/80">
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
            <div className="text-2xl font-bold text-theme-success-fg">
              {new Set((currentWorker.roles || []).flatMap(role => getRolePermissions(role))).size}
            </div>
            <div className="text-theme-secondary">Total Permissions</div>
          </div>
        </div>
      </div>
    </div>
  );
};
