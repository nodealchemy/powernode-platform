
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import { X } from 'lucide-react';
import type { ProvidersFilters } from '@/shared/types/ai';

interface AiProviderFiltersProps {
  filters: ProvidersFilters;
  onFiltersChange: (filters: Partial<ProvidersFilters>) => void;
}

export const AiProviderFilters: React.FC<AiProviderFiltersProps> = ({
  filters,
  onFiltersChange
}) => {
  const handleClearFilters = () => {
    onFiltersChange({
      provider_type: undefined,
      capability: undefined,
      search: undefined,
      sort: 'priority'
    });
  };

  const hasActiveFilters = filters.provider_type || filters.capability || filters.search;

  return (
    <div className="bg-theme-surface p-4 rounded-lg border border-theme space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-theme-primary">Filters</h3>
        {hasActiveFilters && (
          <Button
            variant="ghost"
            size="sm"
            onClick={handleClearFilters}
            className="h-8 px-2 text-theme-tertiary hover:text-theme-primary"
          >
            <X className="h-4 w-4 mr-1" />
            Clear
          </Button>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Provider Type
          </label>
          <Select
            value={filters.provider_type || ''}
            onChange={(value) => onFiltersChange({ provider_type: value || undefined })}
          >
            <option value="">All Types</option>
            <option value="text_generation">Text Generation</option>
            <option value="image_generation">Image Generation</option>
            <option value="audio_generation">Audio Generation</option>
            <option value="video_generation">Video Generation</option>
            <option value="code_execution">Code Execution</option>
            <option value="embedding">Embedding</option>
          </Select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Capability
          </label>
          <Select
            value={filters.capability || ''}
            onChange={(value) => onFiltersChange({ capability: value || undefined })}
          >
            <option value="">All Capabilities</option>
            <option value="chat">Chat</option>
            <option value="text_generation">Text Generation</option>
            <option value="vision">Vision</option>
            <option value="function_calling">Function Calling</option>
            <option value="code_execution">Code Execution</option>
            <option value="image_generation">Image Generation</option>
            <option value="embeddings">Embeddings</option>
          </Select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Sort By
          </label>
          <Select
            value={filters.sort || 'priority'}
            onChange={(value) => onFiltersChange({ sort: value as 'name' | 'priority' | 'created_at' })}
          >
            <option value="priority">Priority</option>
            <option value="name">Name</option>
            <option value="created_at">Date Created</option>
            <option value="provider_type">Type</option>
          </Select>
        </div>
      </div>
    </div>
  );
};