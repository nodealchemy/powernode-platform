import React, { useState } from 'react';
import { X, Plus } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import { SOURCE_TYPE_OPTIONS, SOURCE_TYPE_PRESETS } from './sourceTypeLabels';

interface CreateDataSourceModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export const CreateDataSourceModal: React.FC<CreateDataSourceModalProps> = ({
  isOpen,
  onClose,
  onSuccess
}) => {
  const [submitting, setSubmitting] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    slug: '',
    source_type: 'custom',
    description: '',
    api_base_url: '',
    requires_auth: true,
    rate_limit_minute: '',
    rate_limit_hour: '',
    rate_limit_day: '',
  });

  const { addNotification } = useNotifications();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);

    try {
      const rateLimits: Record<string, number> = {};
      if (formData.rate_limit_minute) rateLimits.requests_per_minute = parseInt(formData.rate_limit_minute, 10);
      if (formData.rate_limit_hour) rateLimits.requests_per_hour = parseInt(formData.rate_limit_hour, 10);
      if (formData.rate_limit_day) rateLimits.requests_per_day = parseInt(formData.rate_limit_day, 10);

      await dataSourcesApi.createDataSource({
        name: formData.name,
        source_type: formData.source_type,
        slug: formData.slug,
        description: formData.description,
        api_base_url: formData.api_base_url || undefined,
        requires_auth: formData.requires_auth,
        rate_limits: Object.keys(rateLimits).length > 0 ? rateLimits : undefined,
        is_active: true,
      });

      addNotification({
        type: 'success',
        title: 'Data Source Created',
        message: `${formData.name} has been created successfully`
      });

      onSuccess();
      onClose();

      // Reset form
      setFormData({
        name: '',
        slug: '',
        source_type: 'custom',
        description: '',
        api_base_url: '',
        requires_auth: true,
        rate_limit_minute: '',
        rate_limit_hour: '',
        rate_limit_day: '',
      });
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Creation Failed',
        message: 'Failed to create data source. Please try again.'
      });
    } finally {
      setSubmitting(false);
    }
  };

  const handleInputChange = (field: string, value: string | boolean) => {
    setFormData(prev => ({ ...prev, [field]: value }));

    // Auto-generate slug from name
    if (field === 'name' && typeof value === 'string') {
      const slug = value.toLowerCase().replace(/[^a-z0-9]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
      setFormData(prev => ({ ...prev, slug }));
    }

    // Auto-fill from preset when source type changes
    if (field === 'source_type' && typeof value === 'string') {
      const preset = SOURCE_TYPE_PRESETS[value];
      if (preset && value !== 'custom') {
        setFormData(prev => ({
          ...prev,
          source_type: value,
          description: prev.description || preset.description,
          api_base_url: preset.api_base_url,
          requires_auth: preset.requires_auth,
          rate_limit_minute: preset.rate_limits.requests_per_minute?.toString() || '',
          rate_limit_hour: preset.rate_limits.requests_per_hour?.toString() || '',
          rate_limit_day: preset.rate_limits.requests_per_day?.toString() || '',
        }));
      }
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} size="lg">
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <h2 className="text-xl font-semibold text-theme-primary">Create Data Source</h2>
        <Button
          variant="ghost"
          size="sm"
          onClick={onClose}
          className="h-8 w-8 p-0"
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      <form onSubmit={handleSubmit} className="p-6 space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Name *
            </label>
            <Input
              value={formData.name}
              onChange={(e) => handleInputChange('name', e.target.value)}
              placeholder="e.g., NOAA Climate Data"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Slug *
            </label>
            <Input
              value={formData.slug}
              onChange={(e) => handleInputChange('slug', e.target.value)}
              placeholder="noaa-climate-data"
              required
            />
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Source Type *
          </label>
          <Select
            value={formData.source_type}
            onChange={(value) => handleInputChange('source_type', value)}
          >
            <option value="">Select a source type</option>
            {SOURCE_TYPE_OPTIONS.map(({ value, label }) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </Select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Description
          </label>
          <textarea
            value={formData.description}
            onChange={(e) => handleInputChange('description', e.target.value)}
            placeholder="Brief description of the data source..."
            rows={3}
            className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-info focus:border-transparent"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            API Base URL
          </label>
          <Input
            value={formData.api_base_url}
            onChange={(e) => handleInputChange('api_base_url', e.target.value)}
            placeholder="https://api.datasource.com/v1"
            type="url"
          />
        </div>

        <div>
          <label className="flex items-center space-x-2">
            <input
              type="checkbox"
              checked={formData.requires_auth}
              onChange={(e) => handleInputChange('requires_auth', e.target.checked)}
              className="rounded border-theme-300 text-theme-info focus:ring-theme-info"
            />
            <span className="text-sm text-theme-secondary">Requires Authentication</span>
          </label>
          {formData.source_type !== 'custom' && SOURCE_TYPE_PRESETS[formData.source_type]?.auth_instructions && (
            <p className="mt-1 text-xs text-theme-tertiary">
              {SOURCE_TYPE_PRESETS[formData.source_type].auth_instructions}
            </p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-2">
            Rate Limits
          </label>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Per Minute</label>
              <Input
                value={formData.rate_limit_minute}
                onChange={(e) => handleInputChange('rate_limit_minute', e.target.value)}
                placeholder="e.g., 60"
                type="number"
              />
            </div>
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Per Hour</label>
              <Input
                value={formData.rate_limit_hour}
                onChange={(e) => handleInputChange('rate_limit_hour', e.target.value)}
                placeholder="e.g., 1000"
                type="number"
              />
            </div>
            <div>
              <label className="block text-xs text-theme-tertiary mb-1">Per Day</label>
              <Input
                value={formData.rate_limit_day}
                onChange={(e) => handleInputChange('rate_limit_day', e.target.value)}
                placeholder="e.g., 10000"
                type="number"
              />
            </div>
          </div>
        </div>

        <div className="flex items-center justify-end space-x-3 pt-4 border-t border-theme">
          <Button
            type="button"
            variant="outline"
            onClick={onClose}
            disabled={submitting}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            disabled={submitting || !formData.name || !formData.slug}
            className="flex items-center gap-2"
          >
            <Plus className="h-4 w-4" />
            {submitting ? 'Creating...' : 'Create Data Source'}
          </Button>
        </div>
      </form>
    </Modal>
  );
};
