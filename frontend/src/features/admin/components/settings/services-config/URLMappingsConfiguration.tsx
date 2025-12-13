import React from 'react';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import {
  Globe,
  Plus,
  Edit,
  Trash2,
  ToggleLeft,
  ToggleRight
} from 'lucide-react';
import type { URLMappingsConfigurationProps } from './types';

export const URLMappingsConfiguration: React.FC<URLMappingsConfigurationProps> = ({
  config,
  onToggleMapping,
  onDeleteMapping,
  onEditMapping,
  onAddMapping
}) => {
  const sortedMappings = config.url_mappings.sort((a, b) => (a.priority || 999) - (b.priority || 999));

  return (
    <div className="space-y-6">
      <FlexBetween>
        <h3 className="text-lg font-medium text-theme-primary">URL Mappings</h3>
        <Button onClick={onAddMapping} variant="primary" size="sm">
          <Plus className="w-4 h-4 mr-2" />
          Add Mapping
        </Button>
      </FlexBetween>

      <div className="space-y-4">
        {sortedMappings.map((mapping) => (
          <Card key={mapping.id} className="p-4">
            <FlexBetween className="mb-3">
              <div>
                <FlexItemsCenter className="mb-1">
                  <h4 className="font-medium text-theme-primary mr-3">
                    {mapping.name || mapping.pattern}
                  </h4>
                  <Badge variant={mapping.enabled ? 'success' : 'secondary'} size="sm">
                    {mapping.enabled ? 'Active' : 'Disabled'}
                  </Badge>
                  <Badge variant="info" size="sm" className="ml-2">
                    Priority: {mapping.priority}
                  </Badge>
                </FlexItemsCenter>
                <div className="text-sm text-theme-secondary">
                  {mapping.pattern} → {mapping.target_service}
                </div>
                {mapping.description && (
                  <div className="text-sm text-theme-tertiary mt-1">
                    {mapping.description}
                  </div>
                )}
              </div>

              <FlexItemsCenter gap="xs">
                <Button
                  onClick={() => onToggleMapping(mapping.id)}
                  variant="secondary"
                  size="sm"
                >
                  {mapping.enabled ? (
                    <ToggleRight className="w-4 h-4" />
                  ) : (
                    <ToggleLeft className="w-4 h-4" />
                  )}
                </Button>
                <Button
                  onClick={() => onEditMapping(mapping)}
                  variant="secondary"
                  size="sm"
                >
                  <Edit className="w-4 h-4" />
                </Button>
                <Button
                  onClick={() => onDeleteMapping(mapping.id)}
                  variant="danger"
                  size="sm"
                >
                  <Trash2 className="w-4 h-4" />
                </Button>
              </FlexItemsCenter>
            </FlexBetween>

            <div className="flex flex-wrap gap-2">
              {mapping.methods.map((method) => (
                <Badge key={method} variant="secondary" size="sm">
                  {method}
                </Badge>
              ))}
            </div>
          </Card>
        ))}

        {sortedMappings.length === 0 && (
          <Card className="p-8 text-center">
            <Globe className="w-12 h-12 mx-auto mb-4 text-theme-secondary" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">
              No URL Mappings
            </h3>
            <p className="text-theme-secondary mb-4">
              Add URL mappings to configure request routing.
            </p>
            <Button onClick={onAddMapping} variant="primary">
              <Plus className="w-4 h-4 mr-2" />
              Add Your First Mapping
            </Button>
          </Card>
        )}
      </div>
    </div>
  );
};
