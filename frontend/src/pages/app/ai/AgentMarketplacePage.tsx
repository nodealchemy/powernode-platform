// Agent Marketplace Page - Browse and install pre-built AI agent templates
import React, { useState, useEffect } from 'react';
import { Plus, Search, Filter, Store, Star, Download, Grid, List } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  agentMarketplaceApi,
  AgentTemplate,
  AgentInstallation,
  MarketplaceCategory,
  TemplateFilters
} from '@/shared/services/ai/AgentMarketplaceApiService';

// Type guard for API errors
interface ApiErrorResponse {
  response?: {
    data?: {
      error?: string;
    };
  };
}

function isApiError(error: unknown): error is ApiErrorResponse {
  return typeof error === 'object' && error !== null && 'response' in error;
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (isApiError(error)) {
    return error.response?.data?.error || fallback;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return fallback;
}

const AgentMarketplacePage: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const [templates, setTemplates] = useState<AgentTemplate[]>([]);
  const [featuredTemplates, setFeaturedTemplates] = useState<AgentTemplate[]>([]);
  const [categories, setCategories] = useState<MarketplaceCategory[]>([]);
  const [installations, setInstallations] = useState<AgentInstallation[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string>('all');
  const [verticalFilter, setVerticalFilter] = useState<string>('all');
  const [pricingFilter, setPricingFilter] = useState<string>('all');
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');

  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'ai',
    onDataUpdate: () => {
      loadTemplates();
    }
  });

  useEffect(() => {
    loadData();
  }, []);

  useEffect(() => {
    loadTemplates();
  }, [searchQuery, categoryFilter, verticalFilter, pricingFilter]);

  const loadData = async () => {
    try {
      setLoading(true);
      const [templatesRes, categoriesRes, installationsRes, featuredRes] = await Promise.all([
        agentMarketplaceApi.getTemplates(),
        agentMarketplaceApi.getCategories(),
        agentMarketplaceApi.getInstallations(),
        agentMarketplaceApi.getFeaturedTemplates()
      ]);
      setTemplates(templatesRes.items || []);
      setCategories(categoriesRes.categories || []);
      setInstallations(installationsRes.items || []);
      setFeaturedTemplates(featuredRes.templates || []);
    } catch {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load marketplace data')
      }));
    } finally {
      setLoading(false);
    }
  };

  const loadTemplates = async () => {
    try {
      const filters: TemplateFilters = {};
      if (searchQuery) filters.query = searchQuery;
      if (categoryFilter !== 'all') filters.category = categoryFilter;
      if (verticalFilter !== 'all') filters.vertical = verticalFilter;
      if (pricingFilter !== 'all') filters.pricing_type = pricingFilter;

      const data = await agentMarketplaceApi.getTemplates(filters);
      setTemplates(data.items || []);
    } catch {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to load templates')
      }));
    }
  };

  const handleInstall = async (template: AgentTemplate) => {
    try {
      await agentMarketplaceApi.installTemplate(template.id);
      dispatch(addNotification({
        type: 'success',
        message: `"${template.name}" installed successfully`
      }));
      // Reload installations
      const installationsRes = await agentMarketplaceApi.getInstallations();
      setInstallations(installationsRes.items || []);
    } catch {
      dispatch(addNotification({
        type: 'error',
        message: getErrorMessage(error, 'Failed to install template')
      }));
    }
  };

  const isInstalled = (templateId: string): boolean => {
    return installations.some(i => i.template.id === templateId && i.status === 'active');
  };

  const getPricingLabel = (template: AgentTemplate): string => {
    if (template.pricing_type === 'free') return 'Free';
    if (template.price_usd) return `$${template.price_usd}`;
    if (template.monthly_price_usd) return `$${template.monthly_price_usd}/mo`;
    return 'Premium';
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Agent Marketplace' }
  ];

  return (
    <PageContainer
      title="Agent Marketplace"
      description="Pre-built vertical AI agents and templates for rapid deployment"
      breadcrumbs={breadcrumbs}
      actions={[
        {
          label: 'My Installations',
          onClick: () => {},
          icon: Download,
          variant: 'secondary' as const
        },
        {
          label: 'Publish Template',
          onClick: () => {},
          icon: Plus,
          variant: 'primary' as const
        }
      ]}
    >
      {/* Search and Filters */}
      <div className="flex flex-wrap gap-4 mb-6">
        <div className="flex-1 min-w-64">
          <div className="relative">
            <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-theme-secondary" />
            <input
              type="search"
              placeholder="Search templates..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Filter size={16} className="text-theme-secondary" />
          <select
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="all">All Categories</option>
            {categories.map(cat => (
              <option key={cat.id} value={cat.slug}>{cat.name}</option>
            ))}
          </select>
        </div>

        <div className="flex items-center gap-2">
          <select
            value={verticalFilter}
            onChange={(e) => setVerticalFilter(e.target.value)}
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="all">All Verticals</option>
            <option value="saas">SaaS</option>
            <option value="devops">DevOps</option>
            <option value="finance">Finance</option>
            <option value="support">Support</option>
            <option value="sales">Sales</option>
          </select>
        </div>

        <div className="flex items-center gap-2">
          <select
            value={pricingFilter}
            onChange={(e) => setPricingFilter(e.target.value)}
            className="px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            <option value="all">All Pricing</option>
            <option value="free">Free</option>
            <option value="one_time">One-time</option>
            <option value="subscription">Subscription</option>
            <option value="freemium">Freemium</option>
          </select>
        </div>

        <div className="flex gap-1 border border-theme rounded-md">
          <button
            onClick={() => setViewMode('grid')}
            className={`p-2 ${viewMode === 'grid' ? 'bg-theme-interactive-primary text-theme-on-primary' : 'bg-theme-surface text-theme-secondary'}`}
          >
            <Grid size={16} />
          </button>
          <button
            onClick={() => setViewMode('list')}
            className={`p-2 ${viewMode === 'list' ? 'bg-theme-interactive-primary text-theme-on-primary' : 'bg-theme-surface text-theme-secondary'}`}
          >
            <List size={16} />
          </button>
        </div>
      </div>

      {/* Featured Templates */}
      {featuredTemplates.length > 0 && (
        <div className="mb-8">
          <h2 className="text-lg font-semibold text-theme-primary mb-4">Featured Templates</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {featuredTemplates.slice(0, 3).map(template => (
              <div key={template.id} className="bg-theme-surface border-2 border-theme-accent rounded-lg p-4">
                <div className="flex justify-between items-start mb-2">
                  <h3 className="font-medium text-theme-primary">{template.name}</h3>
                  <span className="text-xs px-2 py-1 bg-theme-interactive-primary text-theme-on-primary rounded">Featured</span>
                </div>
                <p className="text-sm text-theme-secondary mb-3">{template.description}</p>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    {template.average_rating && (
                      <span className="flex items-center gap-1 text-sm text-theme-secondary">
                        <Star size={14} className="text-theme-warning" />
                        {template.average_rating.toFixed(1)}
                      </span>
                    )}
                    <span className="text-sm text-theme-secondary">
                      {template.installation_count} installs
                    </span>
                  </div>
                  <span className="text-sm font-medium text-theme-accent">{getPricingLabel(template)}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Templates Grid/List */}
      {loading ? (
        <div className="text-center py-12">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-theme-accent border-t-theme-primary"></div>
          <p className="mt-4 text-theme-secondary">Loading templates...</p>
        </div>
      ) : templates.length === 0 ? (
        <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
          <Store size={48} className="mx-auto text-theme-secondary mb-4" />
          <h3 className="text-lg font-semibold text-theme-primary mb-2">No templates found</h3>
          <p className="text-theme-secondary mb-6">
            Try adjusting your filters or search query
          </p>
        </div>
      ) : (
        <div data-testid="marketplace-templates-grid" className={viewMode === 'grid' ? 'grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4' : 'space-y-4'}>
          {templates.map(template => (
            <div key={template.id} data-testid="template-card" className="bg-theme-surface border border-theme rounded-lg p-4 hover:border-theme-accent transition-colors cursor-pointer">
              <div className="flex justify-between items-start mb-2">
                <div>
                  <h3 data-testid="template-title" className="font-medium text-theme-primary">{template.name}</h3>
                  <p className="text-xs text-theme-secondary">{template.publisher.name}</p>
                </div>
                {template.is_verified && (
                  <span className="text-xs px-2 py-1 bg-theme-success/10 text-theme-success rounded">Verified</span>
                )}
              </div>
              <p className="text-sm text-theme-secondary mb-3 line-clamp-2">{template.description}</p>
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-3">
                  {template.average_rating && (
                    <span className="flex items-center gap-1 text-sm text-theme-secondary">
                      <Star size={14} className="text-theme-warning" />
                      {template.average_rating.toFixed(1)} ({template.review_count})
                    </span>
                  )}
                  <span className="text-sm text-theme-secondary">
                    {template.installation_count} installs
                  </span>
                </div>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-theme-accent">{getPricingLabel(template)}</span>
                {isInstalled(template.id) ? (
                  <span className="text-sm text-theme-success font-medium">Installed</span>
                ) : (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleInstall(template);
                    }}
                    className="btn-theme btn-theme-primary btn-theme-sm"
                  >
                    Install
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </PageContainer>
  );
};

export default AgentMarketplacePage;
