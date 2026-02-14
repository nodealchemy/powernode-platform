import React from 'react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiProvider } from '@/shared/types/ai';

interface ProviderMetricsTabProps {
  provider: AiProvider;
}

export const ProviderMetricsTab: React.FC<ProviderMetricsTabProps> = ({ provider }) => {
  return (
    <Card>
      <CardHeader title="Provider Capabilities" />
      <CardContent>
        {provider.capabilities && provider.capabilities.length > 0 ? (
          <div className="flex flex-wrap gap-2">
            {provider.capabilities.map(capability => (
              <Badge key={capability} variant="outline">
                {capability.replace('_', ' ')}
              </Badge>
            ))}
          </div>
        ) : (
          <p className="text-theme-muted">No capabilities defined for this provider.</p>
        )}
      </CardContent>
    </Card>
  );
};
