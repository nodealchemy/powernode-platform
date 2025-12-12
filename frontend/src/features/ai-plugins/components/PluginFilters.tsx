
import { Select } from '@/shared/components/ui/Select';
import { Card } from '@/shared/components/ui/Card';

interface PluginFiltersProps {
  filters: {
    type?: string;
    status?: string;
    verified?: boolean;
    official?: boolean;
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onFiltersChange: (filters: any) => void;
}

export const PluginFilters: React.FC<PluginFiltersProps> = ({
  filters,
  onFiltersChange
}) => {
  const handleFilterChange = (key: string, value: string) => {
    onFiltersChange({
      ...filters,
      [key]: value === '' ? undefined : value
    });
  };

  return (
    <Card className="p-4">
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        {/* Plugin Type Filter */}
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-2">
            Plugin Type
          </label>
          <Select
            value={filters.type || ''}
            onValueChange={(value) => handleFilterChange('type', value)}
            options={[
              { value: '', label: 'All Types' },
              { value: 'ai_provider', label: 'AI Provider' },
              { value: 'workflow_node', label: 'Workflow Node' },
              { value: 'integration', label: 'Integration' },
              { value: 'webhook', label: 'Webhook' },
              { value: 'tool', label: 'Tool' }
            ]}
          />
        </div>

        {/* Status Filter */}
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-2">
            Status
          </label>
          <Select
            value={filters.status || ''}
            onValueChange={(value) => handleFilterChange('status', value)}
            options={[
              { value: '', label: 'All Status' },
              { value: 'available', label: 'Available' },
              { value: 'installed', label: 'Installed' },
              { value: 'deprecated', label: 'Deprecated' }
            ]}
          />
        </div>

        {/* Verified Filter */}
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-2">
            Verification
          </label>
          <Select
            value={filters.verified === true ? 'verified' : filters.verified === false ? 'unverified' : ''}
            onValueChange={(value) => {
              handleFilterChange('verified', value === 'verified' ? 'true' : value === 'unverified' ? 'false' : '');
            }}
            options={[
              { value: '', label: 'All Plugins' },
              { value: 'verified', label: 'Verified Only' },
              { value: 'unverified', label: 'Unverified Only' }
            ]}
          />
        </div>

        {/* Official Filter */}
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-2">
            Source
          </label>
          <Select
            value={filters.official === true ? 'official' : filters.official === false ? 'community' : ''}
            onValueChange={(value) => {
              handleFilterChange('official', value === 'official' ? 'true' : value === 'community' ? 'false' : '');
            }}
            options={[
              { value: '', label: 'All Sources' },
              { value: 'official', label: 'Official Only' },
              { value: 'community', label: 'Community Only' }
            ]}
          />
        </div>
      </div>
    </Card>
  );
};
