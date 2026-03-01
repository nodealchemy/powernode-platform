import React, { useState } from 'react';
import { Check, Shield, Lock, Eye, Settings, Search } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface Permission {
  id: string;
  resource: string;
  action: string;
  description: string;
  key: string;
}

interface Role {
  id: string;
  name: string;
  description: string;
}

interface PermissionSelectorProps {
  selectedRoleId?: string;
  selectedPermissionIds: string[];
  onPermissionChange: (permissionIds: string[]) => void;
  onRoleChange: (roleId: string) => void;
  availableRoles: Role[];
  availablePermissions: Permission[];
  loading?: boolean;
  mode?: 'role-only' | 'permissions-only' | 'both';
  disabled?: boolean;
}

export const PermissionSelector: React.FC<PermissionSelectorProps> = ({
  selectedRoleId,
  selectedPermissionIds,
  onPermissionChange,
  onRoleChange,
  availableRoles,
  availablePermissions,
  loading = false,
  mode = 'both',
  disabled = false
}) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedResource, setSelectedResource] = useState<string | null>(null);

  // Get unique resources for filtering
  const resources = Array.from(new Set(availablePermissions.map(p => p.resource))).sort();

  // Filter permissions based on search and resource filter
  const filteredPermissions = availablePermissions.filter(permission => {
    const matchesSearch = permission.key.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         permission.description.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesResource = !selectedResource || permission.resource === selectedResource;
    return matchesSearch && matchesResource;
  });

  // Group permissions by resource
  const groupedPermissions = filteredPermissions.reduce((acc, permission) => {
    if (!acc[permission.resource]) {
      acc[permission.resource] = [];
    }
    acc[permission.resource].push(permission);
    return acc;
  }, {} as Record<string, Permission[]>);

  const handlePermissionToggle = (permissionId: string) => {
    if (disabled) return;
    
    const isSelected = selectedPermissionIds.includes(permissionId);
    if (isSelected) {
      onPermissionChange(selectedPermissionIds.filter(id => id !== permissionId));
    } else {
      onPermissionChange([...selectedPermissionIds, permissionId]);
    }
  };

  const handleSelectAllInResource = (resource: string) => {
    if (disabled) return;
    
    const resourcePermissions = availablePermissions.filter(p => p.resource === resource);
    const resourcePermissionIds = resourcePermissions.map(p => p.id);
    const allSelected = resourcePermissionIds.every(id => selectedPermissionIds.includes(id));
    
    if (allSelected) {
      // Deselect all in resource
      onPermissionChange(selectedPermissionIds.filter(id => !resourcePermissionIds.includes(id)));
    } else {
      // Select all in resource
      const newSelection = Array.from(new Set([...selectedPermissionIds, ...resourcePermissionIds]));
      onPermissionChange(newSelection);
    }
  };

  const getResourceIcon = (resource: string) => {
    switch (resource) {
      case 'users': return <Shield className="w-4 h-4" />;
      case 'accounts': return <Settings className="w-4 h-4" />;
      case 'billing': return <Eye className="w-4 h-4" />;
      case 'analytics': return <Lock className="w-4 h-4" />;
      default: return <Shield className="w-4 h-4" />;
    }
  };

  const getActionColor = (action: string) => {
    switch (action) {
      case 'read': return 'text-theme-info bg-theme-info-background';
      case 'create': return 'text-theme-success bg-theme-success-background';
      case 'update': return 'text-theme-warning bg-theme-warning-background';
      case 'delete': return 'text-theme-error bg-theme-error-background';
      case 'export': return 'text-theme-info bg-theme-info-background';
      case 'global': return 'text-theme-warning bg-theme-warning-background';
      default: return 'text-theme-secondary bg-theme-background-secondary';
    }
  };

  if (loading) {
    return (
      <LoadingSpinner className="p-8" />
    );
  }

  return (
    <div className="space-y-6">
      {/* Role Selection */}
      {(mode === 'role-only' || mode === 'both') && (
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-2">
            Role (Optional)
          </label>
          <select
            value={selectedRoleId || ''}
            onChange={(e) => onRoleChange(e.target.value)}
            className="w-full px-3 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-focus focus:border-transparent bg-theme-background"
            disabled={disabled}
          >
            <option value="">Select a role (optional)</option>
            {availableRoles.map(role => (
              <option key={role.id} value={role.id}>
                {role.name} - {role.description}
              </option>
            ))}
          </select>
          {selectedRoleId && (
            <p className="text-sm text-theme-secondary mt-1">
              Selected role provides base permissions. You can add specific permissions below.
            </p>
          )}
        </div>
      )}

      {/* Permission Selection */}
      {(mode === 'permissions-only' || mode === 'both') && (
        <div>
          <div className="flex items-center justify-between mb-4">
            <label className="block text-sm font-medium text-theme-secondary">
              Specific Permissions {mode === 'both' && '(Optional)'}
            </label>
            <span className="text-sm text-theme-tertiary">
              {selectedPermissionIds.length} selected
            </span>
          </div>

          {/* Search and Filter */}
          <div className="flex gap-4 mb-4">
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-secondary w-4 h-4" />
              <input
                type="text"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                placeholder="Search permissions..."
                className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-focus focus:border-transparent bg-theme-background"
                disabled={disabled}
              />
            </div>
            <select
              value={selectedResource || ''}
              onChange={(e) => setSelectedResource(e.target.value || null)}
              className="px-3 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-focus focus:border-transparent bg-theme-background"
              disabled={disabled}
            >
              <option value="">All Resources</option>
              {resources.map(resource => (
                <option key={resource} value={resource}>
                  {resource.charAt(0).toUpperCase() + resource.slice(1)}
                </option>
              ))}
            </select>
          </div>

          {/* Permissions List */}
          <div className="border border-theme rounded-lg bg-theme-surface">
            <div className="max-h-64 overflow-y-auto">
              {Object.entries(groupedPermissions).map(([resource, permissions]) => (
                <div key={resource} className="border-b border-theme last:border-b-0">
                  <div 
                    className="flex items-center justify-between p-3 bg-theme-background-secondary hover:bg-theme-surface-hover cursor-pointer"
                    onClick={() => handleSelectAllInResource(resource)}
                  >
                    <div className="flex items-center gap-2">
                      {getResourceIcon(resource)}
                      <span className="font-medium text-theme-primary capitalize">
                        {resource}
                      </span>
                      <span className="text-sm text-theme-secondary">
                        ({permissions.length})
                      </span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-theme-tertiary">
                        {permissions.filter(p => selectedPermissionIds.includes(p.id)).length} selected
                      </span>
                      {permissions.every(p => selectedPermissionIds.includes(p.id)) ? (
                        <Check className="w-4 h-4 text-theme-success" />
                      ) : permissions.some(p => selectedPermissionIds.includes(p.id)) ? (
                        <div className="w-4 h-4 bg-theme-info rounded-sm"></div>
                      ) : (
                        <div className="w-4 h-4 border-2 border-theme rounded-sm"></div>
                      )}
                    </div>
                  </div>
                  
                  {permissions.map(permission => {
                    const isSelected = selectedPermissionIds.includes(permission.id);
                    return (
                      <div
                        key={permission.id}
                        className={`flex items-center justify-between p-3 pl-8 hover:bg-theme-surface-hover cursor-pointer transition-colors ${
                          isSelected ? 'bg-theme-info-background' : ''
                        }`}
                        onClick={() => handlePermissionToggle(permission.id)}
                      >
                        <div className="flex-1">
                          <div className="flex items-center gap-2">
                            <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${getActionColor(permission.action)}`}>
                              {permission.action}
                            </span>
                            <span className="font-medium text-theme-primary">
                              {permission.key}
                            </span>
                          </div>
                          <p className="text-sm text-theme-secondary mt-1">
                            {permission.description}
                          </p>
                        </div>
                        <div className="ml-4">
                          {isSelected ? (
                            <div className="w-5 h-5 bg-theme-info rounded flex items-center justify-center">
                              <Check className="w-3 h-3 text-white" />
                            </div>
                          ) : (
                            <div className="w-5 h-5 border-2 border-theme rounded"></div>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          </div>

          {filteredPermissions.length === 0 && (
            <div className="text-center py-8 text-theme-secondary">
              <Shield className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
              <p>No permissions found matching your criteria</p>
            </div>
          )}

          {mode === 'both' && selectedPermissionIds.length === 0 && !selectedRoleId && (
            <div className="mt-4 p-3 bg-theme-warning-background border border-theme-warning rounded-lg">
              <p className="text-sm text-theme-warning">
                <strong>Note:</strong> Please select either a role or specific permissions to create the delegation.
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
};