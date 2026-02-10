import React, { useState, useEffect } from 'react';
import { Save, X } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useCreateMcpApp, useUpdateMcpApp, useGetMcpApp } from '../api/mcpAppsApi';
import type { McpAppType, McpAppStatus, CreateMcpAppParams } from '../types/mcpApps';

const APP_TYPES: McpAppType[] = ['custom', 'template', 'system'];
const APP_STATUSES: McpAppStatus[] = ['draft', 'published', 'archived'];

interface McpAppConfiguratorProps {
  appId?: string;
  onClose: () => void;
  onSaved: () => void;
}

export const McpAppConfigurator: React.FC<McpAppConfiguratorProps> = ({
  appId,
  onClose,
  onSaved,
}) => {
  const { addNotification } = useNotifications();
  const { data: existingApp } = useGetMcpApp(appId || '');
  const createApp = useCreateMcpApp();
  const updateApp = useUpdateMcpApp();

  const [formData, setFormData] = useState<CreateMcpAppParams>({
    name: '',
    description: '',
    app_type: 'custom',
    status: 'draft',
    version: '1.0.0',
    html_content: '',
  });

  const isEdit = !!appId;

  useEffect(() => {
    if (existingApp) {
      setFormData({
        name: existingApp.name,
        description: existingApp.description || '',
        app_type: existingApp.app_type,
        status: existingApp.status,
        version: existingApp.version,
        html_content: existingApp.html_content || '',
        input_schema: existingApp.input_schema,
        output_schema: existingApp.output_schema,
        metadata: existingApp.metadata,
        csp_policy: existingApp.csp_policy,
        sandbox_config: existingApp.sandbox_config,
      });
    }
  }, [existingApp]);

  const handleChange = (field: keyof CreateMcpAppParams, value: string) => {
    setFormData((prev) => ({ ...prev, [field]: value }));
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();

    if (isEdit && appId) {
      updateApp.mutate(
        { id: appId, ...formData },
        {
          onSuccess: () => {
            addNotification({ type: 'success', message: 'App updated' });
            onSaved();
          },
          onError: () => {
            addNotification({ type: 'error', message: 'Failed to update app' });
          },
        }
      );
    } else {
      createApp.mutate(formData, {
        onSuccess: () => {
          addNotification({ type: 'success', message: 'App created' });
          onSaved();
        },
        onError: () => {
          addNotification({ type: 'error', message: 'Failed to create app' });
        },
      });
    }
  };

  const isPending = createApp.isPending || updateApp.isPending;

  return (
    <Card className="p-5">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-theme-primary">
          {isEdit ? 'Edit App' : 'Create App'}
        </h3>
        <Button variant="ghost" size="xs" onClick={onClose}>
          <X className="h-4 w-4" />
        </Button>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Name */}
        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            Name
          </label>
          <input
            type="text"
            value={formData.name}
            onChange={(e) => handleChange('name', e.target.value)}
            required
            className="w-full px-3 py-2 text-sm border border-theme rounded-lg bg-theme-bg text-theme-primary placeholder:text-theme-muted focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
            placeholder="My MCP App"
          />
        </div>

        {/* Description */}
        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            Description
          </label>
          <textarea
            value={formData.description || ''}
            onChange={(e) => handleChange('description', e.target.value)}
            rows={2}
            className="w-full px-3 py-2 text-sm border border-theme rounded-lg bg-theme-bg text-theme-primary placeholder:text-theme-muted focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent resize-none"
            placeholder="What does this app do?"
          />
        </div>

        {/* Type + Status + Version */}
        <div className="grid grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">
              Type
            </label>
            <select
              value={formData.app_type}
              onChange={(e) => handleChange('app_type', e.target.value)}
              className="w-full px-3 py-2 text-sm border border-theme rounded-lg bg-theme-bg text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
            >
              {APP_TYPES.map((type) => (
                <option key={type} value={type}>
                  {type}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">
              Status
            </label>
            <select
              value={formData.status || 'draft'}
              onChange={(e) => handleChange('status', e.target.value)}
              className="w-full px-3 py-2 text-sm border border-theme rounded-lg bg-theme-bg text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
            >
              {APP_STATUSES.map((status) => (
                <option key={status} value={status}>
                  {status}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">
              Version
            </label>
            <input
              type="text"
              value={formData.version || ''}
              onChange={(e) => handleChange('version', e.target.value)}
              className="w-full px-3 py-2 text-sm border border-theme rounded-lg bg-theme-bg text-theme-primary placeholder:text-theme-muted focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              placeholder="1.0.0"
              pattern="\d+\.\d+\.\d+"
              title="Semver format: X.Y.Z"
            />
          </div>
        </div>

        {/* HTML Content */}
        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            HTML Content
          </label>
          <textarea
            value={formData.html_content || ''}
            onChange={(e) => handleChange('html_content', e.target.value)}
            rows={8}
            className="w-full px-3 py-2 text-sm font-mono border border-theme rounded-lg bg-theme-bg text-theme-primary placeholder:text-theme-muted focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent resize-y"
            placeholder="<html>...</html>"
          />
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="secondary" size="sm" onClick={onClose} type="button">
            Cancel
          </Button>
          <Button variant="primary" size="sm" type="submit" loading={isPending}>
            <Save className="h-4 w-4 mr-1" />
            {isEdit ? 'Update' : 'Create'}
          </Button>
        </div>
      </form>
    </Card>
  );
};
