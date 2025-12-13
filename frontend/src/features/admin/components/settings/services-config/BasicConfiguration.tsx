import React from 'react';
import { FlexBetween } from '@/shared/components/ui/FlexContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { ToggleLeft, ToggleRight } from 'lucide-react';
import type { BasicConfigurationProps } from './types';

export const BasicConfiguration: React.FC<BasicConfigurationProps> = ({
  config,
  updateConfig
}) => {
  return (
    <div className="space-y-6">
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Basic Settings</h3>

        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable Services Proxy
              </label>
              <p className="text-sm text-theme-secondary">
                Enable service proxy functionality for load balancing and routing
              </p>
            </div>
            <Button
              onClick={() => updateConfig({ enabled: !config.enabled })}
              variant={config.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.enabled ? (
                <ToggleRight className="w-4 h-4 mr-2" />
              ) : (
                <ToggleLeft className="w-4 h-4 mr-2" />
              )}
              {config.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Current Environment
            </label>
            <select
              value={config.current_environment}
              onChange={(e) => updateConfig({ current_environment: e.target.value })}
              className="w-full max-w-xs p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
            >
              <option value="development">Development</option>
              <option value="staging">Staging</option>
              <option value="production">Production</option>
            </select>
          </div>
        </div>
      </Card>
    </div>
  );
};
