import React from 'react';
import { ExternalLink } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import type { AiProvider } from '@/shared/types/ai';

interface ProviderOverviewTabProps {
  provider: AiProvider;
}

export const ProviderOverviewTab: React.FC<ProviderOverviewTabProps> = ({ provider }) => {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <Card>
        <CardHeader title="Provider Information" />
        <CardContent className="space-y-4">
          <div>
            <label className="text-sm font-medium text-theme-muted">Name</label>
            <p className="mt-1 text-theme-primary">{provider.name}</p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-muted">Slug</label>
            <p className="mt-1 text-theme-primary">{provider.slug}</p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-muted">Description</label>
            <p className="mt-1 text-theme-primary break-words">{provider.description}</p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-muted">Base URL</label>
            <p className="mt-1 text-theme-primary font-mono text-xs break-all overflow-hidden">{provider.api_base_url}</p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-muted">Active</label>
            <p className="mt-1 text-theme-primary">{provider.is_active ? 'Yes' : 'No'}</p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader title="External Links" />
        <CardContent className="space-y-4">
          {provider.documentation_url && (
            <div>
              <label className="text-sm font-medium text-theme-muted">Documentation</label>
              <div className="mt-1">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => window.open(provider.documentation_url, '_blank')}
                  className="flex items-center gap-1"
                >
                  <ExternalLink className="h-3 w-3" />
                  View Documentation
                </Button>
              </div>
            </div>
          )}
          {provider.status_url && (
            <div>
              <label className="text-sm font-medium text-theme-muted">Status Page</label>
              <div className="mt-1">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => window.open(provider.status_url, '_blank')}
                  className="flex items-center gap-1"
                >
                  <ExternalLink className="h-3 w-3" />
                  View Status
                </Button>
              </div>
            </div>
          )}
          {!provider.documentation_url && !provider.status_url && (
            <p className="text-theme-muted">No external links available</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
};
