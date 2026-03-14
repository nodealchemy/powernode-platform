import React, { useState } from 'react';
import { Package, Search, FileText } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { formatDateTime } from '@/shared/utils/formatters';

interface ContainerSbom {
  id: string;
  format: string;
  component_count: number;
  components: Array<{
    name: string;
    version: string;
    type: string;
    licenses: string[];
  }>;
  generated_at: string;
}

interface ContainerSbomViewerProps {
  sbom: ContainerSbom | null;
  loading: boolean;
  error?: string | null;
}

export const ContainerSbomViewer: React.FC<ContainerSbomViewerProps> = ({
  sbom,
  loading,
  error,
}) => {
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState('');

  if (loading) {
    return (
      <Card className="p-6">
        <div className="flex justify-center items-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="p-6">
        <div className="text-center py-12 text-theme-error">{error}</div>
      </Card>
    );
  }

  if (!sbom) {
    return (
      <Card className="p-6">
        <div className="text-center py-12 text-theme-muted">
          <FileText className="w-12 h-12 mx-auto mb-4 opacity-50" />
          <p>No SBOM data available</p>
        </div>
      </Card>
    );
  }

  const uniqueTypes = [...new Set(sbom.components.map((c) => c.type))];

  const filteredComponents = sbom.components.filter((component) => {
    const matchesSearch =
      component.name.toLowerCase().includes(search.toLowerCase()) ||
      component.version.toLowerCase().includes(search.toLowerCase());
    const matchesType = !typeFilter || component.type === typeFilter;
    return matchesSearch && matchesType;
  });

  return (
    <div className="space-y-4">
      <Card className="p-4">
        <div className="flex items-center justify-between flex-wrap gap-4">
          <div className="flex items-center gap-4">
            <Badge variant="info" size="lg">
              {sbom.format.toUpperCase()}
            </Badge>
            <span className="text-theme-secondary">
              <span className="font-medium text-theme-primary">{sbom.component_count}</span> components
            </span>
          </div>
          <span className="text-sm text-theme-muted">
            Generated: {formatDateTime(sbom.generated_at)}
          </span>
        </div>
      </Card>

      <Card className="p-4">
        <div className="flex items-center gap-4 flex-wrap">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-secondary" />
            <input
              type="text"
              placeholder="Search components..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            />
          </div>

          <select
            value={typeFilter}
            onChange={(e) => setTypeFilter(e.target.value)}
            className="px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
          >
            <option value="">All Types</option>
            {uniqueTypes.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>
      </Card>

      <Card className="p-0">
        <div className="max-h-96 overflow-y-auto">
          {filteredComponents.length === 0 ? (
            <div className="text-center py-8 text-theme-muted">
              No components match your filters
            </div>
          ) : (
            <div className="divide-y divide-theme">
              {filteredComponents.map((component, index) => (
                <div
                  key={index}
                  className="p-4 hover:bg-theme-surface-hover transition-colors"
                >
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-3">
                      <Package className="w-5 h-5 text-theme-secondary flex-shrink-0" />
                      <div>
                        <p className="font-medium text-theme-primary">{component.name}</p>
                        <p className="text-sm text-theme-secondary">{component.version}</p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge variant="outline" size="sm">
                        {component.type}
                      </Badge>
                    </div>
                  </div>
                  {component.licenses.length > 0 && (
                    <div className="mt-2 ml-8 flex flex-wrap gap-1">
                      {component.licenses.map((license, licenseIndex) => (
                        <Badge key={licenseIndex} variant="secondary" size="xs">
                          {license}
                        </Badge>
                      ))}
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </Card>
    </div>
  );
};
