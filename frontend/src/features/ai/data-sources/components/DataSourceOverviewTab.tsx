import React from 'react';
import { ExternalLink } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { humanizeSourceType } from './sourceTypeLabels';
import type { AiDataSource } from '@/shared/types/ai';

interface DataSourceOverviewTabProps {
  dataSource: AiDataSource;
}

export const DataSourceOverviewTab: React.FC<DataSourceOverviewTabProps> = ({ dataSource }) => {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <Card>
        <CardHeader title="Data Source Information" />
        <CardContent className="space-y-4">
          <div>
            <label className="text-sm font-medium text-theme-tertiary">Name</label>
            <p className="mt-1 text-theme-primary">{dataSource.name}</p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-tertiary">Slug</label>
            <p className="mt-1 text-theme-primary">{dataSource.slug}</p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-tertiary">Source Type</label>
            <p className="mt-1 text-theme-primary">
              {humanizeSourceType(dataSource.source_type)}
            </p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-tertiary">Category</label>
            <p className="mt-1 text-theme-primary capitalize">
              {dataSource.category || 'Uncategorized'}
            </p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-tertiary">Protocol</label>
            <p className="mt-1 text-theme-primary uppercase">
              {dataSource.protocol || 'rest'}
            </p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-tertiary">Description</label>
            <p className="mt-1 text-theme-primary break-words">{dataSource.description || 'No description'}</p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-tertiary">Base URL</label>
            <p className="mt-1 text-theme-primary font-mono text-xs break-all overflow-hidden">
              {dataSource.api_base_url || 'Not configured'}
            </p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-tertiary">Active</label>
            <p className="mt-1 text-theme-primary">{dataSource.is_active ? 'Yes' : 'No'}</p>
          </div>
          <div>
            <label className="text-sm font-medium text-theme-tertiary">Requires Auth</label>
            <p className="mt-1 text-theme-primary">{dataSource.requires_auth ? 'Yes' : 'No'}</p>
          </div>
          {dataSource.last_health_check_at && (
            <div>
              <label className="text-sm font-medium text-theme-tertiary">Last Health Check</label>
              <p className="mt-1 text-theme-primary">
                {new Date(dataSource.last_health_check_at).toLocaleString()}
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      <div className="space-y-4">
        {/* Capabilities */}
        <Card>
          <CardHeader title="Capabilities" />
          <CardContent>
            {dataSource.capabilities && dataSource.capabilities.length > 0 ? (
              <div className="flex flex-wrap gap-2">
                {dataSource.capabilities.map(capability => (
                  <Badge key={capability} variant="outline">
                    {capability.replace(/_/g, ' ')}
                  </Badge>
                ))}
              </div>
            ) : (
              <p className="text-theme-tertiary">No capabilities defined for this data source.</p>
            )}
          </CardContent>
        </Card>

        {/* Configuration */}
        {dataSource.configuration && Object.keys(dataSource.configuration).length > 0 && (
          <Card>
            <CardHeader title="Configuration" />
            <CardContent>
              <pre className="text-xs text-theme-primary bg-theme-surface-secondary p-3 rounded-lg overflow-auto max-h-48">
                {JSON.stringify(dataSource.configuration, null, 2)}
              </pre>
            </CardContent>
          </Card>
        )}

        {/* External Links */}
        <Card>
          <CardHeader title="External Links" />
          <CardContent className="space-y-4">
            {dataSource.documentation_url ? (
              <div>
                <label className="text-sm font-medium text-theme-tertiary">Documentation</label>
                <div className="mt-1">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => window.open(dataSource.documentation_url, '_blank')}
                    className="flex items-center gap-1"
                  >
                    <ExternalLink className="h-3 w-3" />
                    View Documentation
                  </Button>
                </div>
              </div>
            ) : (
              <p className="text-theme-tertiary">No external links available</p>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
};
