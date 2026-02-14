import React from 'react';
import { RefreshCw, TestTube } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiProvider } from '@/shared/types/ai';

function formatModelSize(sizeBytes: number): string {
  if (!sizeBytes) return 'Unknown';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let size = sizeBytes;
  let unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return `${size.toFixed(1)} ${units[unitIndex]}`;
}

interface ProviderModelsTabProps {
  provider: AiProvider;
  canManageProviders: boolean;
  syncing: boolean;
  onSyncModels: () => void;
}

export const ProviderModelsTab: React.FC<ProviderModelsTabProps> = ({
  provider,
  canManageProviders,
  syncing,
  onSyncModels,
}) => {
  return (
    <Card>
      <CardHeader
        title="Available Models"
        action={canManageProviders ? (
          <Button
            variant="outline"
            size="sm"
            onClick={onSyncModels}
            disabled={syncing}
          >
            <RefreshCw className={`h-4 w-4 mr-2 ${syncing ? 'animate-spin' : ''}`} />
            {syncing ? 'Syncing...' : 'Sync Models'}
          </Button>
        ) : undefined}
      />
      <CardContent>
        <div className="mb-4">
          <p className="text-theme-primary font-medium">
            {provider.model_count ?? 0} model{(provider.model_count ?? 0) !== 1 ? 's' : ''} available
          </p>
          <p className="text-sm text-theme-muted">
            Models are synced from the provider API
          </p>
        </div>

        {provider.supported_models && provider.supported_models.length > 0 ? (
          <div className="space-y-3">
            {provider.supported_models.map((model, index) => (
              <div
                key={model.id || index}
                className="p-4 border border-theme-border rounded-lg hover:bg-theme-surface-hover transition-colors"
              >
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-2">
                      <h4 className="font-medium text-theme-primary">{model.name}</h4>
                      <Badge variant="outline" size="sm">{model.id}</Badge>
                    </div>
                    {model.description && (
                      <p className="text-sm text-theme-muted mb-2">{model.description}</p>
                    )}
                    <div className="flex flex-wrap gap-2 text-xs text-theme-muted">
                      {model.context_length && (
                        <span className="px-2 py-1 bg-theme-surface rounded">
                          Context: {typeof model.context_length === 'string' ? model.context_length : `${model.context_length} tokens`}
                        </span>
                      )}
                      {model.parameter_size && (
                        <span className="px-2 py-1 bg-theme-surface rounded">
                          Parameters: {model.parameter_size}
                        </span>
                      )}
                      {model.family && (
                        <span className="px-2 py-1 bg-theme-surface rounded">
                          Family: {model.family}
                        </span>
                      )}
                      {model.quantization_level && (
                        <span className="px-2 py-1 bg-theme-surface rounded">
                          Quantization: {model.quantization_level}
                        </span>
                      )}
                      {model.size_bytes && (
                        <span className="px-2 py-1 bg-theme-surface rounded">
                          Size: {formatModelSize(model.size_bytes)}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-center py-8">
            <TestTube className="h-8 w-8 text-theme-muted mx-auto mb-2" />
            <p className="text-theme-muted">No models available</p>
            <p className="text-sm text-theme-muted">
              {canManageProviders ? 'Click "Sync Models" to fetch available models' : 'Contact an administrator to sync models'}
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
