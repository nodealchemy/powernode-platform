import React from 'react';
import { FlexBetween } from '@/shared/components/ui/FlexContainer';
import { GridCols2 } from '@/shared/components/ui/GridContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import type { AdvancedConfigurationProps } from './types';

export const AdvancedConfiguration: React.FC<AdvancedConfigurationProps> = ({
  config,
  updateConfig
}) => {
  return (
    <div className="space-y-6">
      {/* Load Balancing */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Load Balancing</h3>
        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable Load Balancing
              </label>
              <p className="text-sm text-theme-secondary">
                Distribute requests across multiple backend instances
              </p>
            </div>
            <Button
              onClick={() => updateConfig({
                load_balancing: { ...config.load_balancing, enabled: !config.load_balancing.enabled }
              })}
              variant={config.load_balancing.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.load_balancing.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>

          {config.load_balancing.enabled && (
            <div className="space-y-4 pl-4 border-l-2 border-theme">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Algorithm
                </label>
                <select
                  value={config.load_balancing.algorithm}
                  onChange={(e) => updateConfig({
                    load_balancing: { ...config.load_balancing, algorithm: e.target.value as 'round_robin' | 'least_connections' | 'ip_hash' }
                  })}
                  className="w-full max-w-xs p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                >
                  <option value="round_robin">Round Robin</option>
                  <option value="least_connections">Least Connections</option>
                  <option value="ip_hash">IP Hash</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Health Check Interval (seconds)
                </label>
                <input
                  type="number"
                  value={config.load_balancing.health_check_interval}
                  onChange={(e) => updateConfig({
                    load_balancing: { ...config.load_balancing, health_check_interval: parseInt(e.target.value) }
                  })}
                  className="w-full max-w-xs p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  min="5"
                  max="300"
                />
              </div>
            </div>
          )}
        </div>
      </Card>

      {/* SSL Configuration */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">SSL/TLS Configuration</h3>
        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable SSL/TLS
              </label>
              <p className="text-sm text-theme-secondary">
                Enable HTTPS with SSL/TLS encryption
              </p>
            </div>
            <Button
              onClick={() => updateConfig({
                ssl_config: { ...config.ssl_config, enabled: !config.ssl_config.enabled }
              })}
              variant={config.ssl_config.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.ssl_config.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>

          {config.ssl_config.enabled && (
            <div className="space-y-4 pl-4 border-l-2 border-theme">
              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Enforce HTTPS
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Redirect all HTTP requests to HTTPS
                  </p>
                </div>
                <Button
                  onClick={() => updateConfig({
                    ssl_config: { ...config.ssl_config, enforce_https: !config.ssl_config.enforce_https }
                  })}
                  variant={config.ssl_config.enforce_https ? 'success' : 'secondary'}
                  size="sm"
                >
                  {config.ssl_config.enforce_https ? 'Yes' : 'No'}
                </Button>
              </FlexBetween>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Certificate Path
                </label>
                <input
                  type="text"
                  value={config.ssl_config.certificate_path}
                  onChange={(e) => updateConfig({
                    ssl_config: { ...config.ssl_config, certificate_path: e.target.value }
                  })}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="/etc/ssl/certs/powernode.crt"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Private Key Path
                </label>
                <input
                  type="text"
                  value={config.ssl_config.private_key_path}
                  onChange={(e) => updateConfig({
                    ssl_config: { ...config.ssl_config, private_key_path: e.target.value }
                  })}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="/etc/ssl/private/powernode.key"
                />
              </div>
            </div>
          )}
        </div>
      </Card>

      {/* CORS Configuration */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">CORS Configuration</h3>
        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable CORS
              </label>
              <p className="text-sm text-theme-secondary">
                Configure Cross-Origin Resource Sharing policies
              </p>
            </div>
            <Button
              onClick={() => updateConfig({
                cors_config: { ...config.cors_config, enabled: !config.cors_config.enabled }
              })}
              variant={config.cors_config.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.cors_config.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>

          {config.cors_config.enabled && (
            <div className="space-y-4 pl-4 border-l-2 border-theme">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Allowed Origins (one per line)
                </label>
                <textarea
                  value={config?.cors_config?.allowed_origins?.join('\n') || ''}
                  onChange={(e) => updateConfig({
                    cors_config: {
                      ...config?.cors_config,
                      allowed_origins: e.target.value.split('\n').filter(o => o.trim())
                    }
                  })}
                  rows={3}
                  className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  placeholder="https://app.powernode.io&#10;https://admin.powernode.io&#10;*"
                />
              </div>

              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Allow Credentials
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Allow credentials in cross-origin requests
                  </p>
                </div>
                <Button
                  onClick={() => updateConfig({
                    cors_config: { ...config?.cors_config, credentials: !config?.cors_config?.credentials }
                  })}
                  variant={config?.cors_config?.credentials ? 'success' : 'secondary'}
                  size="sm"
                >
                  {config?.cors_config?.credentials ? 'Yes' : 'No'}
                </Button>
              </FlexBetween>
            </div>
          )}
        </div>
      </Card>

      {/* Rate Limiting */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Rate Limiting</h3>
        <div className="space-y-4">
          <FlexBetween>
            <div>
              <label className="block text-sm font-medium text-theme-primary">
                Enable Rate Limiting
              </label>
              <p className="text-sm text-theme-secondary">
                Limit request rates to prevent abuse
              </p>
            </div>
            <Button
              onClick={() => updateConfig({
                rate_limiting: { ...config.rate_limiting, enabled: !config.rate_limiting.enabled }
              })}
              variant={config.rate_limiting.enabled ? 'success' : 'secondary'}
              size="sm"
            >
              {config.rate_limiting.enabled ? 'Enabled' : 'Disabled'}
            </Button>
          </FlexBetween>

          {config.rate_limiting.enabled && (
            <div className="space-y-4 pl-4 border-l-2 border-theme">
              <GridCols2 gap="md">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Requests per Hour
                  </label>
                  <input
                    type="number"
                    value={config.rate_limiting.default_limit}
                    onChange={(e) => updateConfig({
                      rate_limiting: { ...config.rate_limiting, default_limit: parseInt(e.target.value) }
                    })}
                    className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                    min="1"
                    max="100000"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Burst Limit
                  </label>
                  <input
                    type="number"
                    value={config.rate_limiting.burst_limit}
                    onChange={(e) => updateConfig({
                      rate_limiting: { ...config.rate_limiting, burst_limit: parseInt(e.target.value) }
                    })}
                    className="w-full p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                    min="1"
                    max="10000"
                  />
                </div>
              </GridCols2>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
};
