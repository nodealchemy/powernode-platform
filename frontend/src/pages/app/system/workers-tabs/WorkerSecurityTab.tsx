import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { Shield, UserCheck, AlertTriangle, Activity, RefreshCw } from 'lucide-react';
import type { WorkerSecurityTabProps } from './types';

export const WorkerSecurityTab: React.FC<WorkerSecurityTabProps> = ({
  workers,
  canManageWorkers,
  onRefresh
}) => {
  const getSecurityStats = () => {
    const totalPermissions = new Set(workers.flatMap(w => w.permissions)).size;
    const totalRoles = new Set(workers.flatMap(w => w.roles)).size;
    const expiredTokens = 0; // Would need to be calculated based on actual token expiry
    const securityEvents = 0; // Would need to be fetched from audit logs

    return { totalPermissions, totalRoles, expiredTokens, securityEvents };
  };

  const securityStats = getSecurityStats();

  return (
    <div className="space-y-6">
      {/* Security Overview */}
      <Card className="p-6">
        <FlexBetween className="mb-4">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Security Overview</h3>
            <p className="text-sm text-theme-secondary">
              Monitor worker security status and permissions
            </p>
          </div>
          <Button onClick={onRefresh} variant="secondary" size="sm">
            <RefreshCw className="w-4 h-4 mr-2" />
            Refresh
          </Button>
        </FlexBetween>

        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="p-4 bg-theme-surface rounded-lg">
            <FlexItemsCenter className="mb-2">
              <Shield className="w-4 h-4 text-theme-primary mr-2" />
              <span className="text-sm text-theme-secondary">Total Roles</span>
            </FlexItemsCenter>
            <div className="text-2xl font-bold text-theme-primary">{securityStats.totalRoles}</div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <FlexItemsCenter className="mb-2">
              <UserCheck className="w-4 h-4 text-theme-info mr-2" />
              <span className="text-sm text-theme-secondary">Permissions</span>
            </FlexItemsCenter>
            <div className="text-2xl font-bold text-theme-info">{securityStats.totalPermissions}</div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <FlexItemsCenter className="mb-2">
              <AlertTriangle className="w-4 h-4 text-theme-warning mr-2" />
              <span className="text-sm text-theme-secondary">Expired Tokens</span>
            </FlexItemsCenter>
            <div className="text-2xl font-bold text-theme-warning">{securityStats.expiredTokens}</div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <FlexItemsCenter className="mb-2">
              <Activity className="w-4 h-4 text-theme-success mr-2" />
              <span className="text-sm text-theme-secondary">Security Events</span>
            </FlexItemsCenter>
            <div className="text-2xl font-bold text-theme-success">{securityStats.securityEvents}</div>
          </div>
        </div>
      </Card>

      {/* Security Actions */}
      {canManageWorkers && (
        <Card className="p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Security Actions</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <Button variant="secondary" className="h-auto p-4 text-left justify-start">
              <div>
                <div className="font-medium text-theme-primary mb-1">Rotate All Tokens</div>
                <div className="text-sm text-theme-secondary">Generate new tokens for all workers</div>
              </div>
            </Button>
            <Button variant="secondary" className="h-auto p-4 text-left justify-start">
              <div>
                <div className="font-medium text-theme-primary mb-1">Audit Permissions</div>
                <div className="text-sm text-theme-secondary">Review and audit worker permissions</div>
              </div>
            </Button>
            <Button variant="secondary" className="h-auto p-4 text-left justify-start">
              <div>
                <div className="font-medium text-theme-primary mb-1">Security Report</div>
                <div className="text-sm text-theme-secondary">Generate security compliance report</div>
              </div>
            </Button>
          </div>
        </Card>
      )}

      {/* Worker Security Status */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Worker Security Status</h3>
        <div className="space-y-3">
          {workers
            .sort((a, b) => {
              // System workers first
              const aIsSystem = a.account_name === 'System';
              const bIsSystem = b.account_name === 'System';

              if (aIsSystem && !bIsSystem) return -1;
              if (!aIsSystem && bIsSystem) return 1;

              return a.name.localeCompare(b.name);
            })
            .map((worker) => {
              const isSystemWorker = worker.account_name === 'System';
              return (
                <div
                  key={worker.id}
                  className={`p-4 border border-theme rounded-lg ${
                    isSystemWorker ? 'bg-gradient-to-r from-theme-info/5 to-transparent border-theme-info/30' : ''
                  }`}
                >
                  <FlexBetween>
                    <div>
                      <div className="font-medium text-theme-primary">
                        {worker.name}
                        {isSystemWorker && (
                          <span className="ml-2 px-2 py-0.5 text-xs bg-theme-info/10 text-theme-info rounded-full">
                            SYSTEM
                          </span>
                        )}
                      </div>
                      <div className="text-sm text-theme-secondary">
                        {worker.roles.length} roles, {worker.permissions.length} permissions
                      </div>
                    </div>
                    <div className="flex items-center space-x-2">
                      <Badge
                        variant={worker.status === 'active' ? 'success' : 'secondary'}
                        size="sm"
                      >
                        {worker.status}
                      </Badge>
                      {canManageWorkers && (
                        <Button
                          variant="secondary"
                          size="sm"
                          title="View worker details"
                        >
                          <Shield className="w-4 h-4" />
                        </Button>
                      )}
                    </div>
                  </FlexBetween>
                </div>
              );
            })}
        </div>
      </Card>
    </div>
  );
};
