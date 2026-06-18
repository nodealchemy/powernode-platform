import React, { useState } from 'react';
import { X, Plus } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { dataSourcesApi } from '@/shared/services/ai/DataSourcesApiService';
import {
  SUGGESTED_SOURCE_TYPE_OPTIONS,
  SOURCE_TYPE_PRESETS,
  DATA_SOURCE_PROTOCOL_OPTIONS,
  SUGGESTED_CATEGORIES,
} from './sourceTypeLabels';
import type { DataSourceProtocol } from '@/shared/types/ai';

interface CreateDataSourceModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

// Suggested category for a known source type — mirrors the backend backfill
// mapping. Free-form sources return '' (the user picks/types a category).
function inferCategoryFromSourceType(sourceType: string): string {
  if (sourceType.startsWith('noaa_') || sourceType === 'open_meteo') return 'weather';
  if (sourceType === 'fred' || sourceType === 'yahoo_finance') return 'finance';
  if (sourceType === 'espn') return 'sports';
  if (sourceType === 'newsapi') return 'news';
  return '';
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
    category: '',
    protocol: 'rest' as DataSourceProtocol,
    description: '',
    api_base_url: '',
    requires_auth: true,
    respect_robots: false,
    crawl_delay_seconds: '',
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
        source_type: formData.source_type.trim(),
        category: formData.category.trim() || undefined,
        protocol: formData.protocol,
        slug: formData.slug,
        description: formData.description,
        api_base_url: formData.api_base_url || undefined,
        requires_auth: formData.requires_auth,
        respect_robots: formData.respect_robots,
        // Only send a crawl delay when one is provided; blank leaves it unset.
        crawl_delay_seconds: formData.crawl_delay_seconds
          ? parseInt(formData.crawl_delay_seconds, 10)
          : undefined,
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
        category: '',
        protocol: 'rest',
        description: '',
        api_base_url: '',
        requires_auth: true,
        respect_robots: false,
        crawl_delay_seconds: '',
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

    // Auto-fill from preset when a KNOWN source type is chosen. Free-form values
    // simply skip the preset (lookup returns undefined) — no enforcement.
    if (field === 'source_type' && typeof value === 'string') {
      const preset = SOURCE_TYPE_PRESETS[value];
      if (preset && value !== 'custom') {
        setFormData(prev => ({
          ...prev,
          source_type: value,
          category: prev.category || inferCategoryFromSourceType(value),
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

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Source Type *
            </label>
            <Input
              value={formData.source_type}
              onChange={(e) => handleInputChange('source_type', e.target.value)}
              list="create-source-type-suggestions"
              placeholder="e.g., open_meteo or crypto_coingecko"
              description="Free-form. Pick a suggestion or type any lowercase token."
              required
            />
            <datalist id="create-source-type-suggestions">
              {SUGGESTED_SOURCE_TYPE_OPTIONS.map(({ value, label }) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </datalist>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Category
            </label>
            <Input
              value={formData.category}
              onChange={(e) => handleInputChange('category', e.target.value)}
              list="create-category-suggestions"
              placeholder="e.g., weather"
              description="Optional grouping label. Backfilled from source type."
            />
            <datalist id="create-category-suggestions">
              {SUGGESTED_CATEGORIES.map((category) => (
                <option key={category} value={category} />
              ))}
            </datalist>
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Protocol *
          </label>
          <Select
            value={formData.protocol}
            onChange={(value) => handleInputChange('protocol', value)}
          >
            {DATA_SOURCE_PROTOCOL_OPTIONS.map(({ value, label }) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </Select>
          <p className="mt-1 text-xs text-theme-tertiary">
            Selects the fetch adapter. REST is the generic default; GraphQL/RSS/Atom use dedicated adapters.
          </p>
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
            className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-info-fg focus:border-transparent"
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
              className="rounded border-theme-300 text-theme-info-fg focus:ring-theme-info-fg"
            />
            <span className="text-sm text-theme-secondary">Requires Authentication</span>
          </label>
          {formData.source_type !== 'custom' && SOURCE_TYPE_PRESETS[formData.source_type]?.auth_instructions && (
            <p className="mt-1 text-xs text-theme-tertiary">
              {SOURCE_TYPE_PRESETS[formData.source_type].auth_instructions}
            </p>
          )}
        </div>

        {/* Crawl politeness — off by default. */}
        <div className="space-y-3 rounded-lg border border-dashed border-theme p-4">
          <label className="flex items-center space-x-2">
            <input
              type="checkbox"
              checked={formData.respect_robots}
              onChange={(e) => handleInputChange('respect_robots', e.target.checked)}
              className="rounded border-theme-300 text-theme-info-fg focus:ring-theme-info-fg"
            />
            <span className="text-sm text-theme-secondary">Respect robots.txt</span>
          </label>
          <p className="text-xs text-theme-tertiary">
            When enabled, the background monitor honors the host&apos;s robots.txt and paces
            requests per host. Off by default.
          </p>
          <div>
            <label className="block text-xs text-theme-tertiary mb-1">Crawl Delay (seconds)</label>
            <Input
              value={formData.crawl_delay_seconds}
              onChange={(e) => handleInputChange('crawl_delay_seconds', e.target.value)}
              placeholder="e.g., 5"
              type="number"
              min={0}
            />
            <p className="mt-1 text-xs text-theme-tertiary">
              Minimum seconds between requests to the same host. A robots.txt Crawl-delay may
              raise it. Leave blank for no per-host delay.
            </p>
          </div>
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
            disabled={submitting || !formData.name || !formData.slug || !formData.source_type.trim()}
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
