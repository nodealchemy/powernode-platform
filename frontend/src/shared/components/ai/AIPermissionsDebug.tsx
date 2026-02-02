import React, { useState } from 'react';
import { useSelector } from 'react-redux';
import { 
  Shield, 
  User, 
  Key, 
  CheckCircle, 
  XCircle, 
  AlertTriangle,
  Copy,
  ChevronDown,
  ChevronRight
} from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { useAuth } from '@/shared/hooks/useAuth';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { RootState } from '@/shared/services';

const AI_PERMISSIONS = [
  'ai.providers.read',
  'ai.providers.create',
  'ai.providers.update',
  'ai.providers.delete',
  'ai.providers.test',
  'ai.agents.read',
  'ai.agents.create',
  'ai.agents.update',
  'ai.agents.delete',
  'ai.agents.manage',
  'ai.workflows.read',
  'ai.workflows.create',
  'ai.workflows.update',
  'ai.workflows.delete',
  'ai.workflows.execute',
  'ai.conversations.read',
  'ai.conversations.create',
  'ai.conversations.update',
  'ai.conversations.delete',
  'ai.analytics.read',
  'ai.analytics.export'
];

interface PermissionCheckProps {
  permission: string;
  hasPermission: boolean;
}

const PermissionCheck: React.FC<PermissionCheckProps> = ({ permission, hasPermission }) => (
  <div className="flex items-center justify-between py-1">
    <span className="text-sm font-mono text-theme-secondary">{permission}</span>
    <div className="flex items-center space-x-2">
      {hasPermission ? (
        <CheckCircle className="h-4 w-4 text-theme-success" />
      ) : (
        <XCircle className="h-4 w-4 text-theme-error" />
      )}
    </div>
  </div>
);

export const AIPermissionsDebug: React.FC = () => {
  const [expanded, setExpanded] = useState(false);
  const [copied, setCopied] = useState(false);
  
  const { currentUser, isAuthenticated } = useAuth();
  const { hasPermission, getAllPermissions, getAllRoles } = usePermissions();
  const authState = useSelector((state: RootState) => state.auth);

  const aiPermissions = AI_PERMISSIONS.filter(permission => hasPermission(permission));
  const missingAIPermissions = AI_PERMISSIONS.filter(permission => !hasPermission(permission));

  const diagnosticInfo = {
    user: currentUser,
    isAuthenticated,
    hasAccessToken: !!authState.access_token,
    hasRefreshToken: !!authState.refresh_token,
    isImpersonating: authState.impersonation.isImpersonating,
    allPermissions: getAllPermissions(),
    allRoles: getAllRoles(),
    aiPermissions,
    missingAIPermissions,
    timestamp: new Date().toISOString()
  };

  const copyDiagnosticInfo = async () => {
    try {
      await navigator.clipboard.writeText(JSON.stringify(diagnosticInfo, null, 2));
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      console.error('Failed to copy diagnostic info:', error);
    }
  };

  const getAuthStatus = () => {
    if (!isAuthenticated) return { status: 'Not Authenticated', variant: 'danger' as const, icon: XCircle };
    if (!authState.access_token) return { status: 'No Access Token', variant: 'warning' as const, icon: AlertTriangle };
    if (aiPermissions.length === 0) return { status: 'No AI Permissions', variant: 'warning' as const, icon: AlertTriangle };
    if (aiPermissions.length < AI_PERMISSIONS.length / 2) return { status: 'Limited AI Access', variant: 'warning' as const, icon: AlertTriangle };
    return { status: 'Full AI Access', variant: 'success' as const, icon: CheckCircle };
  };

  const authStatus = getAuthStatus();
  const StatusIcon = authStatus.icon;

  return (
    <Card className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-semibold text-theme-primary flex items-center space-x-2">
          <Shield className="h-5 w-5" />
          <span>AI Permissions Diagnostic</span>
        </h3>
        <Button
          onClick={copyDiagnosticInfo}
          variant="outline"
          size="sm"
          disabled={copied}
        >
          <Copy className="h-4 w-4 mr-2" />
          {copied ? 'Copied!' : 'Copy Debug Info'}
        </Button>
      </div>

      {/* Authentication Status */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <span className="font-medium text-theme-secondary">Authentication Status</span>
          <Badge variant={authStatus.variant} className="flex items-center space-x-1">
            <StatusIcon className="h-3 w-3" />
            <span>{authStatus.status}</span>
          </Badge>
        </div>

        {currentUser && (
          <div className="bg-theme-surface p-3 rounded-lg">
            <div className="flex items-center space-x-2 mb-2">
              <User className="h-4 w-4 text-theme-secondary" />
              <span className="font-medium text-theme-primary">
                {currentUser.name}
              </span>
              <span className="text-sm text-theme-tertiary">({currentUser.email})</span>
            </div>
            <div className="text-sm text-theme-secondary">
              Account: {currentUser.account.name} • Status: {currentUser.status}
            </div>
            {currentUser.email_verified ? (
              <div className="flex items-center space-x-1 text-sm text-theme-success mt-1">
                <CheckCircle className="h-3 w-3" />
                <span>Email verified</span>
              </div>
            ) : (
              <div className="flex items-center space-x-1 text-sm text-theme-warning mt-1">
                <AlertTriangle className="h-3 w-3" />
                <span>Email not verified</span>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Token Status */}
      <div className="space-y-3">
        <span className="font-medium text-theme-secondary">Token Status</span>
        <div className="grid grid-cols-3 gap-2">
          <div className="flex items-center space-x-2">
            <Key className="h-4 w-4 text-theme-secondary" />
            <span className="text-sm">Access Token</span>
            {authState.access_token ? (
              <CheckCircle className="h-3 w-3 text-theme-success" />
            ) : (
              <XCircle className="h-3 w-3 text-theme-error" />
            )}
          </div>
          <div className="flex items-center space-x-2">
            <Key className="h-4 w-4 text-theme-secondary" />
            <span className="text-sm">Refresh Token</span>
            {authState.refresh_token ? (
              <CheckCircle className="h-3 w-3 text-theme-success" />
            ) : (
              <XCircle className="h-3 w-3 text-theme-error" />
            )}
          </div>
          {authState.impersonation.isImpersonating && (
            <div className="flex items-center space-x-2">
              <User className="h-4 w-4 text-theme-warning" />
              <span className="text-sm text-theme-warning">Impersonating</span>
            </div>
          )}
        </div>
      </div>

      {/* Roles */}
      {currentUser?.roles && currentUser.roles.length > 0 && (
        <div className="space-y-3">
          <span className="font-medium text-theme-secondary">User Roles</span>
          <div className="flex flex-wrap gap-2">
            {currentUser.roles.map(role => (
              <Badge key={role} variant="secondary" size="sm">{role}</Badge>
            ))}
          </div>
        </div>
      )}

      {/* AI Permissions Summary */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <span className="font-medium text-theme-secondary">AI Permissions</span>
          <div className="flex items-center space-x-4">
            <span className="text-sm text-theme-success">✓ {aiPermissions.length}</span>
            <span className="text-sm text-theme-error">✗ {missingAIPermissions.length}</span>
            <Button
              onClick={() => setExpanded(!expanded)}
              variant="ghost"
              size="sm"
              className="p-1"
            >
              {expanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
            </Button>
          </div>
        </div>

        {expanded && (
          <div className="bg-theme-surface p-3 rounded-lg space-y-1">
            {AI_PERMISSIONS.map(permission => (
              <PermissionCheck
                key={permission}
                permission={permission}
                hasPermission={hasPermission(permission)}
              />
            ))}
          </div>
        )}
      </div>

      {/* Recommendations */}
      {!isAuthenticated && (
        <div className="bg-theme-error bg-opacity-5 border border-theme-error p-3 rounded-lg">
          <h4 className="font-medium text-theme-error mb-2">Authentication Required</h4>
          <p className="text-sm text-theme-tertiary">
            You need to sign in to access AI features. Please refresh the page or sign in again.
          </p>
        </div>
      )}

      {isAuthenticated && aiPermissions.length === 0 && (
        <div className="bg-theme-warning bg-opacity-5 border border-theme-warning p-3 rounded-lg">
          <h4 className="font-medium text-theme-warning mb-2">No AI Permissions</h4>
          <p className="text-sm text-theme-tertiary">
            Contact your system administrator to grant AI permissions. You need at least one of the AI permissions to access AI features.
          </p>
        </div>
      )}

      {isAuthenticated && aiPermissions.length > 0 && missingAIPermissions.length > 0 && (
        <div className="bg-theme-info bg-opacity-5 border border-theme-info p-3 rounded-lg">
          <h4 className="font-medium text-theme-info mb-2">Partial AI Access</h4>
          <p className="text-sm text-theme-tertiary">
            You have access to some AI features but may be missing permissions for others. 
            Contact your administrator if you need access to additional AI capabilities.
          </p>
        </div>
      )}
    </Card>
  );
};