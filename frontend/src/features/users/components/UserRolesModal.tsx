import React, { useState, useEffect, useCallback } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usersApi, User } from '../services/usersApi';
import { useNotification } from '@/shared/hooks/useNotification';
import { Shield, Users, UserCheck, UserX, Plus, Minus, Lock } from 'lucide-react';

interface UserRolesModalProps {
  user: User | null;
  isOpen: boolean;
  onClose: () => void;
  onUserUpdated?: () => void;
}

export const UserRolesModal: React.FC<UserRolesModalProps> = ({
  user,
  isOpen,
  onClose,
  onUserUpdated
}) => {
  const { showNotification } = useNotification();
  const [userRoles, setUserRoles] = useState<string[]>([]);
  const [availableRoles, setAvailableRoles] = useState<Array<{ value: string; label: string; description: string; canAssign?: boolean }>>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [pendingChanges, setPendingChanges] = useState<{
    toAdd: string[];
    toRemove: string[];
  }>({ toAdd: [], toRemove: [] });

  // Load user roles and available roles
  useEffect(() => {
    if (!user || !isOpen) return;

    // Reset state when opening the modal
    setUserRoles([...user.roles]);
    setPendingChanges({ toAdd: [], toRemove: [] });
    setLoading(true);

    // Load available roles
    const loadAvailableRoles = async () => {
      try {
        const roles = await usersApi.getAvailableRoles();
        setAvailableRoles(roles || []);
      } catch (error) {
        showNotification('Failed to load available roles', 'error');
        setAvailableRoles([]);
      } finally {
        setLoading(false);
      }
    };

    loadAvailableRoles();
  }, [user, isOpen]); // Removed showNotification as it should be stable

  const toggleRole = (roleValue: string) => {
    const role = availableRoles.find(r => r.value === roleValue);
    const isCurrentlyAssigned = userRoles.includes(roleValue);
    const isRestricted = role && role.canAssign === false;
    
    // For restricted roles, only allow removal if currently assigned
    if (isRestricted && !isCurrentlyAssigned) {
      showNotification('You do not have permission to assign this role', 'warning');
      return;
    }
    
    // For restricted roles that are currently assigned, show a confirmation for removal
    if (isRestricted && isCurrentlyAssigned) {
      const confirmRemoval = window.confirm(
        `You are removing a restricted role "${role.label}". You won't be able to reassign it later. Continue?`
      );
      if (!confirmRemoval) return;
    }
    
    const isPendingAdd = pendingChanges.toAdd.includes(roleValue);
    const isPendingRemove = pendingChanges.toRemove.includes(roleValue);

    setPendingChanges(prev => {
      let newToAdd = [...prev.toAdd];
      let newToRemove = [...prev.toRemove];

      if (isCurrentlyAssigned) {
        // Currently assigned - toggle remove
        if (isPendingRemove) {
          // Cancel removal
          newToRemove = newToRemove.filter(r => r !== roleValue);
        } else {
          // Schedule removal
          newToRemove.push(roleValue);
          newToAdd = newToAdd.filter(r => r !== roleValue);
        }
      } else {
        // Not currently assigned - toggle add
        if (isPendingAdd) {
          // Cancel addition
          newToAdd = newToAdd.filter(r => r !== roleValue);
        } else {
          // Schedule addition
          newToAdd.push(roleValue);
          newToRemove = newToRemove.filter(r => r !== roleValue);
        }
      }

      return { toAdd: newToAdd, toRemove: newToRemove };
    });
  };

  const saveChanges = async () => {
    if (!user || (pendingChanges.toAdd.length === 0 && pendingChanges.toRemove.length === 0)) {
      return;
    }

    try {
      setSaving(true);
      
      // Calculate final roles
      let finalRoles = [...userRoles];
      finalRoles = finalRoles.filter(role => !pendingChanges.toRemove.includes(role));
      finalRoles = [...finalRoles, ...pendingChanges.toAdd];

      // Ensure at least one role
      if (finalRoles.length === 0) {
        showNotification('User must have at least one role assigned', 'error');
        return;
      }

      const response = await usersApi.updateAdminUser(user.id, { roles: finalRoles });
      
      if (response.success) {
        showNotification('User roles updated successfully', 'success');
        setUserRoles(finalRoles);
        setPendingChanges({ toAdd: [], toRemove: [] });
        if (onUserUpdated) {
          onUserUpdated();
        }
        // Close the modal after successful update
        onClose();
      } else {
        showNotification(response.message || 'Failed to update user roles', 'error');
      }
    } catch (error) {
      showNotification('Failed to update user roles', 'error');
    } finally {
      setSaving(false);
    }
  };

  const resetChanges = () => {
    setPendingChanges({ toAdd: [], toRemove: [] });
  };

  const getRoleStatus = (roleValue: string) => {
    const isCurrentlyAssigned = userRoles.includes(roleValue);
    const isPendingAdd = pendingChanges.toAdd.includes(roleValue);
    const isPendingRemove = pendingChanges.toRemove.includes(roleValue);

    if (isCurrentlyAssigned && !isPendingRemove) {
      return 'assigned';
    } else if (isCurrentlyAssigned && isPendingRemove) {
      return 'removing';
    } else if (!isCurrentlyAssigned && isPendingAdd) {
      return 'adding';
    } else {
      return 'unassigned';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'assigned':
        return <UserCheck className="w-4 h-4 text-theme-success" />;
      case 'adding':
        return <Plus className="w-4 h-4 text-theme-interactive-primary" />;
      case 'removing':
        return <Minus className="w-4 h-4 text-theme-error" />;
      default:
        return <UserX className="w-4 h-4 text-theme-tertiary" />;
    }
  };

  const getStatusStyles = (status: string) => {
    switch (status) {
      case 'assigned':
        return 'bg-theme-success bg-opacity-10 border-theme-success border-opacity-40';
      case 'adding':
        return 'bg-theme-surface-hover border-theme-interactive-primary border-opacity-50';
      case 'removing':
        return 'bg-theme-error bg-opacity-10 border-theme-error border-opacity-40';
      default:
        return 'border-theme hover:bg-theme-surface-hover';
    }
  };

  const getTextStyles = (status: string) => {
    switch (status) {
      case 'assigned':
        return {
          label: 'font-medium text-sm text-theme-success',
          description: 'text-xs text-theme-success opacity-75 leading-relaxed'
        };
      case 'adding':
        return {
          label: 'font-medium text-sm text-theme-interactive-primary',
          description: 'text-xs text-theme-interactive-primary opacity-60 leading-relaxed'
        };
      case 'removing':
        return {
          label: 'font-medium text-sm text-theme-error',
          description: 'text-xs text-theme-error opacity-75 leading-relaxed'
        };
      default:
        return {
          label: 'font-medium text-sm text-theme-primary',
          description: 'text-xs text-theme-secondary leading-relaxed'
        };
    }
  };

  const hasChanges = pendingChanges.toAdd.length > 0 || pendingChanges.toRemove.length > 0;

  if (!user) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={() => {
        resetChanges();
        onClose();
      }}
      title={`Manage Roles - ${user.full_name}`}
      maxWidth="3xl"
    >
      <div className="space-y-6">
        {/* User Info Header */}
        <div className="bg-theme-surface-selected border border-theme rounded-xl p-4">
          <div className="flex items-center space-x-4">
            <div className="w-12 h-12 bg-theme-interactive-primary bg-opacity-10 rounded-full flex items-center justify-center">
              <Users className="w-6 h-6 text-theme-interactive-primary" />
            </div>
            <div className="flex-1">
              <h3 className="font-semibold text-theme-primary">{user.full_name}</h3>
              <p className="text-sm text-theme-secondary">{user.email}</p>
            </div>
            <div className="text-right">
              <div className="text-lg font-semibold text-theme-primary">
                {userRoles.length + pendingChanges.toAdd.length - pendingChanges.toRemove.length}
              </div>
              <div className="text-xs text-theme-tertiary">
                {userRoles.length + pendingChanges.toAdd.length - pendingChanges.toRemove.length === 1 ? 'Role' : 'Roles'}
              </div>
            </div>
          </div>
        </div>

        {/* Current Roles Summary */}
        <div className="bg-theme-background border border-theme rounded-xl p-6">
          <div className="flex items-center space-x-3 mb-4">
            <Shield className="w-5 h-5 text-theme-interactive-primary" />
            <h4 className="font-semibold text-theme-primary">Current Roles</h4>
          </div>
          
          {userRoles.length === 0 ? (
            <div className="text-center py-6 text-theme-secondary">
              No roles currently assigned
            </div>
          ) : (
            <div className="flex flex-wrap gap-2">
              {userRoles.map((roleValue, index) => {
                const role = availableRoles.find(r => r.value === roleValue);
                const isPendingRemove = pendingChanges.toRemove.includes(roleValue);
                const isRestricted = role?.canAssign === false;
                return (
                  <Badge 
                    key={index} 
                    className={`${usersApi.getRoleColor([roleValue])} ${
                      isPendingRemove ? 'opacity-50 line-through' : ''
                    } ${isRestricted ? 'relative' : ''}`}
                  >
                    <div className="flex items-center space-x-1">
                      {isRestricted && <Lock className="w-3 h-3" />}
                      <span>
                        {role?.label || roleValue.split('.').map(part => 
                          part.charAt(0).toUpperCase() + part.slice(1)
                        ).join(' ')}
                      </span>
                    </div>
                    {isPendingRemove && <span className="ml-1 text-theme-error">→ Remove</span>}
                    {isRestricted && !isPendingRemove && (
                      <span className="ml-1 text-xs opacity-75">(Restricted)</span>
                    )}
                  </Badge>
                );
              })}
            </div>
          )}

          {/* Show warning for restricted roles */}
          {userRoles.some(roleValue => {
            const role = availableRoles.find(r => r.value === roleValue);
            return role?.canAssign === false;
          }) && (
            <div className="mt-4 pt-3 border-t border-theme">
              <div className="bg-theme-warning-background border border-theme-warning-border rounded-lg p-3">
                <div className="flex items-start space-x-2">
                  <Lock className="w-4 h-4 text-theme-warning mt-0.5 flex-shrink-0" />
                  <div>
                    <p className="text-sm font-medium text-theme-warning">Restricted Roles</p>
                    <p className="text-xs text-theme-warning mt-1 opacity-90">
                      Some assigned roles are marked as restricted because you don't have permission to manage them. 
                      You can only remove these roles, not reassign them.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          )}

          {pendingChanges.toAdd.length > 0 && (
            <div className="mt-4 pt-4 border-t border-theme">
              <h5 className="text-sm font-semibold text-theme-interactive-primary mb-2">Adding:</h5>
              <div className="flex flex-wrap gap-2">
                {pendingChanges.toAdd.map((roleValue, index) => {
                  const role = availableRoles.find(r => r.value === roleValue);
                  return (
                    <Badge key={index} className="bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary border border-theme-interactive-primary border-opacity-20">
                      + {role?.label || roleValue.split('.').map(part => 
                        part.charAt(0).toUpperCase() + part.slice(1)
                      ).join(' ')}
                    </Badge>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        {/* Available Roles */}
        <div className="bg-theme-background border border-theme rounded-xl p-6">
          <h4 className="font-semibold text-theme-primary mb-4">Available Roles</h4>
          
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <LoadingSpinner size="lg" />
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {availableRoles.map((role) => {
                const status = getRoleStatus(role.value);
                const textStyles = getTextStyles(status);
                const isRestricted = role.canAssign === false;
                
                return (
                  <div
                    key={role.value}
                    onClick={() => !isRestricted && toggleRole(role.value)}
                    className={`
                      p-4 rounded-xl border-2 transition-all duration-200
                      ${isRestricted 
                        ? 'cursor-not-allowed opacity-60 bg-theme-surface-hover border-theme' 
                        : 'cursor-pointer'}
                      ${!isRestricted ? getStatusStyles(status) : ''}
                    `}
                  >
                    <div className="flex items-start justify-between">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center space-x-2 mb-1">
                          {isRestricted ? (
                            <Lock className="w-4 h-4 text-theme-tertiary" />
                          ) : (
                            getStatusIcon(status)
                          )}
                          <span className={isRestricted ? 'font-medium text-sm text-theme-tertiary' : textStyles.label}>
                            {role.label}
                          </span>
                          {isRestricted && (
                            <span className="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-theme-warning bg-opacity-10 text-theme-warning border border-theme-warning border-opacity-20">
                              Restricted
                            </span>
                          )}
                        </div>
                        <p className={isRestricted ? 'text-xs text-theme-tertiary leading-relaxed' : textStyles.description}>
                          {isRestricted 
                            ? 'You do not have permission to assign this role' 
                            : role.description}
                        </p>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Actions */}
        <div className="flex items-center justify-between pt-4 border-t border-theme">
          <div className="text-sm text-theme-secondary">
            {hasChanges ? 'You have unsaved changes' : 'Click roles above to assign or remove them'}
          </div>
          <div className="flex space-x-3">
            <Button
              variant="secondary"
              onClick={() => {
                resetChanges();
                onClose();
              }}>
              Cancel
            </Button>
            {hasChanges && (
              <Button
                variant="secondary"
                onClick={resetChanges}
              >
                Reset Changes
              </Button>
            )}
            <Button
              variant="primary"
              onClick={saveChanges}
              disabled={saving || !hasChanges}
            >
              {saving ? 'Saving...' : 'Save Changes'}
            </Button>
          </div>
        </div>
      </div>
    </Modal>
  );
};

export default UserRolesModal;