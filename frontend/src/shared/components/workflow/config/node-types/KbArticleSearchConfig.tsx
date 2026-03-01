import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const KbArticleSearchConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <Input
        label="Search Query"
        value={config.configuration.query || ''}
        onChange={(e) => handleConfigChange('query', e.target.value)}
        placeholder="Full-text search query or {{variable}}"
      />

      <h4 className="text-sm font-medium text-theme-primary mb-2">Filters</h4>

      <Input
        label="Category ID"
        value={config.configuration.category_id || ''}
        onChange={(e) => handleConfigChange('category_id', e.target.value)}
        placeholder="Filter by category ID"
      />

      <EnhancedSelect
        label="Status Filter"
        value={config.configuration.status || ''}
        onChange={(value) => handleConfigChange('status', value)}
        options={[
          { value: '', label: 'All Statuses' },
          { value: 'draft', label: 'Draft' },
          { value: 'review', label: 'In Review' },
          { value: 'published', label: 'Published' },
          { value: 'archived', label: 'Archived' }
        ]}
      />

      <Input
        label="Tags"
        value={Array.isArray(config.configuration.tags) ? config.configuration.tags.join(', ') : (config.configuration.tags || '')}
        onChange={(e) => handleConfigChange('tags', e.target.value)}
        placeholder="tag1, tag2 (comma-separated)"
      />

      <div className="grid grid-cols-2 gap-3">
        <Input
          label="Limit"
          type="number"
          value={config.configuration.limit || 10}
          onChange={(e) => handleConfigChange('limit', parseInt(e.target.value) || 10)}
          min={1}
          max={100}
        />

        <Input
          label="Offset"
          type="number"
          value={config.configuration.offset || 0}
          onChange={(e) => handleConfigChange('offset', parseInt(e.target.value) || 0)}
          min={0}
        />
      </div>

      <EnhancedSelect
        label="Sort By"
        value={config.configuration.sort_by || 'recent'}
        onChange={(value) => handleConfigChange('sort_by', value)}
        options={[
          { value: 'recent', label: 'Most Recent' },
          { value: 'popular', label: 'Most Popular' },
          { value: 'title', label: 'Title (A-Z)' }
        ]}
      />

      <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
        <input
          type="checkbox"
          checked={config.configuration.is_public === true}
          onChange={(e) => handleConfigChange('is_public', e.target.checked ? true : undefined)}
          className="mt-0.5 rounded border-theme-border"
        />
        <div className="flex-1">
          <label className="text-sm font-medium text-theme-primary">Public Only</label>
          <p className="text-xs text-theme-muted mt-1">Show only public articles</p>
        </div>
      </div>

      <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
        <input
          type="checkbox"
          checked={config.configuration.is_featured === true}
          onChange={(e) => handleConfigChange('is_featured', e.target.checked ? true : undefined)}
          className="mt-0.5 rounded border-theme-border"
        />
        <div className="flex-1">
          <label className="text-sm font-medium text-theme-primary">Featured Only</label>
          <p className="text-xs text-theme-muted mt-1">Show only featured articles</p>
        </div>
      </div>

      <Input
        label="Output Variable (Optional)"
        value={config.configuration.output_variable || ''}
        onChange={(e) => handleConfigChange('output_variable', e.target.value)}
        placeholder="search_results"
      />
    </div>
  );
};
