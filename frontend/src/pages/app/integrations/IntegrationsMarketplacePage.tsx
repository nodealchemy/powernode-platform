import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { IntegrationCard } from '@/features/integrations/components/IntegrationCard';
import { integrationsApi } from '@/features/integrations/services/integrationsApi';
import type { IntegrationTemplateSummary, IntegrationType } from '@/features/integrations/types';

export function IntegrationsMarketplacePage() {
  const navigate = useNavigate();
  const [templates, setTemplates] = useState<IntegrationTemplateSummary[]>([]);
  const [featuredTemplates, setFeaturedTemplates] = useState<IntegrationTemplateSummary[]>([]);
  const [categories, setCategories] = useState<Record<string, number>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedType, setSelectedType] = useState<IntegrationType | ''>('');
  const [selectedCategory, setSelectedCategory] = useState('');

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    setIsLoading(true);
    const [templatesRes, featuredRes, categoriesRes] = await Promise.all([
      integrationsApi.getTemplates(1, 100),
      integrationsApi.getTemplates(1, 6, { featured: true }),
      integrationsApi.getTemplateCategories(),
    ]);

    if (templatesRes.success && templatesRes.data) {
      setTemplates(templatesRes.data.templates);
    }
    if (featuredRes.success && featuredRes.data) {
      setFeaturedTemplates(featuredRes.data.templates);
    }
    if (categoriesRes.success && categoriesRes.data) {
      setCategories(categoriesRes.data.categories);
    }
    setIsLoading(false);
  };

  const filteredTemplates = useMemo(() => {
    return templates.filter((template) => {
      const matchesSearch =
        !searchQuery ||
        template.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        template.description?.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesType = !selectedType || template.integration_type === selectedType;
      const matchesCategory = !selectedCategory || template.category === selectedCategory;
      return matchesSearch && matchesType && matchesCategory;
    });
  }, [templates, searchQuery, selectedType, selectedCategory]);

  const integrationTypes: { value: IntegrationType | ''; label: string }[] = [
    { value: '', label: 'All Types' },
    { value: 'github_action', label: 'GitHub Action' },
    { value: 'webhook', label: 'Webhook' },
    { value: 'mcp_server', label: 'MCP Server' },
    { value: 'rest_api', label: 'REST API' },
    { value: 'custom', label: 'Custom' },
  ];

  const hasFilters = searchQuery || selectedType || selectedCategory;

  return (
    <PageContainer
      title="Integration Marketplace"
      description="Browse and install integration templates"
      actions={[
        {
          label: 'My Integrations',
          onClick: () => navigate('/app/integrations'),
          variant: 'secondary',
        },
      ]}
    >
      <div className="space-y-8">
        {/* Featured Section */}
        {!hasFilters && featuredTemplates.length > 0 && (
          <section>
            <h2 className="text-lg font-semibold text-theme-primary mb-4">Featured</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {featuredTemplates.map((template) => (
                <IntegrationCard key={template.id} template={template} />
              ))}
            </div>
          </section>
        )}

        {/* Search and Filters */}
        <section>
          <div className="flex flex-col sm:flex-row gap-4 mb-6">
            <div className="flex-1">
              <input
                type="text"
                placeholder="Search integrations..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              />
            </div>
            <div className="flex gap-2">
              <select
                value={selectedType}
                onChange={(e) => setSelectedType(e.target.value as IntegrationType | '')}
                className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              >
                {integrationTypes.map((type) => (
                  <option key={type.value} value={type.value}>
                    {type.label}
                  </option>
                ))}
              </select>
              <select
                value={selectedCategory}
                onChange={(e) => setSelectedCategory(e.target.value)}
                className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              >
                <option value="">All Categories</option>
                {Object.keys(categories).map((cat) => (
                  <option key={cat} value={cat}>
                    {cat} ({categories[cat]})
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Results */}
          {isLoading ? (
            <div className="flex items-center justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
            </div>
          ) : filteredTemplates.length === 0 ? (
            <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
              <p className="text-theme-secondary">No integrations found</p>
              {hasFilters && (
                <button
                  onClick={() => {
                    setSearchQuery('');
                    setSelectedType('');
                    setSelectedCategory('');
                  }}
                  className="mt-2 text-sm text-theme-primary hover:underline"
                >
                  Clear filters
                </button>
              )}
            </div>
          ) : (
            <>
              {hasFilters && (
                <p className="text-sm text-theme-secondary mb-4">
                  {filteredTemplates.length} integration{filteredTemplates.length !== 1 ? 's' : ''} found
                </p>
              )}
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {filteredTemplates.map((template) => (
                  <IntegrationCard key={template.id} template={template} />
                ))}
              </div>
            </>
          )}
        </section>

        {/* Categories Overview */}
        {!hasFilters && Object.keys(categories).length > 0 && (
          <section>
            <h2 className="text-lg font-semibold text-theme-primary mb-4">
              Browse by Category
            </h2>
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
              {Object.entries(categories).map(([category, count]) => (
                <button
                  key={category}
                  onClick={() => setSelectedCategory(category)}
                  className="p-4 bg-theme-surface border border-theme rounded-lg hover:border-theme-primary transition-colors text-left"
                >
                  <h3 className="font-medium text-theme-primary">{category}</h3>
                  <p className="text-sm text-theme-tertiary mt-1">
                    {count} integration{count !== 1 ? 's' : ''}
                  </p>
                </button>
              ))}
            </div>
          </section>
        )}
      </div>
    </PageContainer>
  );
}
