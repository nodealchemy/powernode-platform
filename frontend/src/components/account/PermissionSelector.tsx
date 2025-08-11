import React, { useState, useEffect } from 'react';
import { Check, X, Shield, Lock, Eye, Settings, Search } from 'lucide-react';

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
      case 'read': return 'text-blue-600 bg-blue-50';
      case 'create': return 'text-green-600 bg-green-50';
      case 'update': return 'text-yellow-600 bg-yellow-50';
      case 'delete': return 'text-red-600 bg-red-50';
      case 'export': return 'text-purple-600 bg-purple-50';
      case 'global': return 'text-orange-600 bg-orange-50';
      default: return 'text-gray-600 bg-gray-50';
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center p-8">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
      </div>
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
                    className="flex items-center justify-between p-3 bg-gray-50 hover:bg-gray-100 cursor-pointer"
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
                        <Check className="w-4 h-4 text-green-600" />
                      ) : permissions.some(p => selectedPermissionIds.includes(p.id)) ? (
                        <div className="w-4 h-4 bg-blue-600 rounded-sm"></div>
                      ) : (
                        <div className="w-4 h-4 border-2 border-gray-300 rounded-sm"></div>
                      )}
                    </div>
                  </div>
                  
                  {permissions.map(permission => {
                    const isSelected = selectedPermissionIds.includes(permission.id);
                    return (
                      <div
                        key={permission.id}
                        className={`flex items-center justify-between p-3 pl-8 hover:bg-gray-50 cursor-pointer transition-colors ${
                          isSelected ? 'bg-blue-50' : ''
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
                            <div className="w-5 h-5 bg-blue-600 rounded flex items-center justify-center">
                              <Check className="w-3 h-3 text-white" />
                            </div>
                          ) : (
                            <div className="w-5 h-5 border-2 border-gray-300 rounded"></div>
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
              <Shield className="w-12 h-12 text-gray-300 mx-auto mb-4" />
              <p>No permissions found matching your criteria</p>
            </div>
          )}

          {mode === 'both' && selectedPermissionIds.length === 0 && !selectedRoleId && (
            <div className="mt-4 p-3 bg-yellow-50 border border-yellow-200 rounded-lg">
              <p className="text-sm text-yellow-700">
                <strong>Note:</strong> Please select either a role or specific permissions to create the delegation.
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
};