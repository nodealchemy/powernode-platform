import React from 'react';
import { Key } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiProviderCredential } from '@/shared/types/ai';

interface ProviderCredentialsTabProps {
  credentials: AiProviderCredential[];
  canManageProviders: boolean;
  onEdit: () => void;
}

export const ProviderCredentialsTab: React.FC<ProviderCredentialsTabProps> = ({
  credentials,
  canManageProviders,
  onEdit,
}) => {
  return (
    <Card>
      <CardHeader
        title="API Credentials"
        action={canManageProviders ? (
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
                className="flex items-center justify-between p-3 border border-theme-border rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <div className={`h-3 w-3 rounded-full ${
                    credential.health_status === 'healthy' ? 'bg-theme-success' : 'bg-theme-error'
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
                      <span>Status: {credential.health_status}</span>
                      {credential.last_used_at && (
                        <span>Last used: {new Date(credential.last_used_at).toLocaleDateString()}</span>
                      )}
                      {credential.consecutive_failures > 0 && (
                        <span className="text-theme-error">
                          {credential.consecutive_failures} recent failures
                        </span>
                      )}
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
              No credentials configured for this provider
            </p>
            {canManageProviders && (
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
