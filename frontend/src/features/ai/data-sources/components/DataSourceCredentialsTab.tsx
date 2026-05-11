import React from 'react';
import { Key } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiDataSourceCredential } from '@/shared/types/ai';

interface DataSourceCredentialsTabProps {
  credentials: AiDataSourceCredential[];
  canManageDataSources: boolean;
  onEdit: () => void;
}

export const DataSourceCredentialsTab: React.FC<DataSourceCredentialsTabProps> = ({
  credentials,
  canManageDataSources,
  onEdit,
}) => {
  return (
    <Card>
      <CardHeader
        title="API Credentials"
        action={canManageDataSources ? (
          <Button variant="outline" onClick={onEdit}>
            <Key className="h-4 w-4 mr-2" />
            Manage Credentials
          </Button>
        ) : undefined}
      />
      <CardContent>
        {credentials && credentials.length > 0 ? (
          <div className="space-y-3">
            {credentials.map((credential) => (
              <div
                key={credential.id}
                className="flex items-center justify-between p-3 border border-theme rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <div className={`h-3 w-3 rounded-full ${
                    credential.last_test_status === 'success' ? 'bg-theme-success' :
                    credential.last_test_status === 'failed' ? 'bg-theme-error' :
                    'bg-theme-muted'
                  }`} />
                  <div>
                    <p className="text-sm font-medium text-theme-primary">
                      {credential.name}
                      {credential.is_default && (
                        <span className="ml-2 px-2 py-1 text-xs bg-theme-info/10 text-theme-info rounded">
                          Default
                        </span>
                      )}
                    </p>
                    <div className="flex items-center gap-4 text-xs text-theme-muted">
                      <span>
                        Status: {credential.last_test_status || 'untested'}
                      </span>
                      {credential.last_used_at && (
                        <span>Last used: {new Date(credential.last_used_at).toLocaleDateString()}</span>
                      )}
                      {credential.consecutive_failures > 0 && (
                        <span className="text-theme-error">
                          {credential.consecutive_failures} recent failures
                        </span>
                      )}
                      <span>
                        {credential.success_count} success / {credential.failure_count} failures
                      </span>
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  {credential.is_active ? (
                    <Badge variant="success" size="sm">Active</Badge>
                  ) : (
                    <Badge variant="secondary" size="sm">Inactive</Badge>
                  )}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-center py-8">
            <Key className="h-8 w-8 mx-auto text-theme-muted mb-2" />
            <p className="text-sm text-theme-muted">
              No credentials configured for this data source
            </p>
            {canManageDataSources && (
              <p className="text-sm text-theme-muted mt-1">
                Click &quot;Manage Credentials&quot; to add credentials
              </p>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
};
