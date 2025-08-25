import React, { useState, useRef, useMemo } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { MarketplaceSearch } from '@/features/marketplace/components/search/MarketplaceSearch';
import { CategoryNavigation } from '@/features/marketplace/components/navigation/CategoryNavigation';
import { AppCardEnhanced } from '@/features/marketplace/components/apps/AppCardEnhanced';
import { PlanComparisonModal } from '@/features/marketplace/components/plans/PlanComparisonModal';
import { AppSubscriptionModal } from '@/features/marketplace/components/apps/AppSubscriptionModal';
import { CreateAppModal } from '@/features/marketplace/components/apps/CreateAppModal';
import { SubscriptionsList } from '@/features/marketplace/components/SubscriptionsList';
import { useMarketplaceListings } from '@/features/marketplace/hooks/useMarketplace';
import { useApps } from '@/features/marketplace/hooks/useApps';
import { appSubscriptionsApi } from '@/features/marketplace/services/appSubscriptionsApi';
import { App, MarketplaceFilters, AppFilters } from '@/features/marketplace/types';
import { MarketplaceFilters as SearchFilters, SearchFacets, ViewMode } from '@/features/marketplace/types/search';
import { RefreshCw, Plus, Sidebar, Filter } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Button } from '@/shared/components/ui/Button';

export const MarketplacePageEnhanced: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  
  // Enhanced search and filter state
  const [searchFilters, setSearchFilters] = useState<SearchFilters>({
    sortBy: 'relevance',
    viewMode: 'grid',
    page: 1,
    perPage: 20
  });
  
  const [appFilters] = useState<AppFilters>({ 
    page: 1, 
    per_page: 20 
  });
  
  // UI state
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showSubscriptionModal, setShowSubscriptionModal] = useState(false);
  const [showPlanComparisonModal, setShowPlanComparisonModal] = useState(false);
  const [selectedAppForSubscription, setSelectedAppForSubscription] = useState<App | null>(null);
  const [selectedAppForComparison, setSelectedAppForComparison] = useState<App | null>(null);
  const [showSidebar, setShowSidebar] = useState(false);
  
  // Refs
  const subscriptionsRefreshRef = useRef<(() => void) | null>(null);
  
  // Determine active tab from URL
  const getActiveTabFromPath = () => {
    const path = location.pathname;
    if (path.includes('/subscriptions')) return 'subscriptions';
    if (path.includes('/reviews')) return 'reviews';
    if (path.includes('/my-apps')) return 'my-apps';
    return 'browse';
  };
  
  const activeTab = getActiveTabFromPath();

  // Convert new SearchFilters to old MarketplaceFilters format
  const legacyFilters: MarketplaceFilters = {
    page: searchFilters.page || 1,
    per_page: searchFilters.perPage || 20,
    status: 'approved'
  };

  const { 
    listings, 
    loading, 
    error, 
    pagination, 
    refresh 
  } = useMarketplaceListings(legacyFilters);

  const { 
    refresh: refreshApps 
  } = useApps(appFilters);

  // Convert listings to apps for the enhanced components
  const apps: App[] = listings.map(listing => ({
    id: listing.app.id,
    name: listing.title,
    slug: listing.app.slug,
    description: listing.long_description || listing.short_description,
    short_description: listing.short_description,
    category: listing.category,
    icon: '📱', // Default icon since AppSummary doesn't have icon
    status: listing.app.status,
    version: '1.0.0', // Default version since AppSummary doesn't have version
    tags: listing.tags,
    created_at: listing.created_at,
    updated_at: listing.updated_at,
    published_at: listing.published_at,
    configuration: {}, // Default empty configuration
    metadata: {}, // Default empty metadata
    plans: listing.app.app_plans || [] // Include app plans from the listing
  }));

  // Mock search facets for demo
  const searchFacets: SearchFacets = {
    categories: [
      { slug: 'developer-tools', name: 'Developer Tools', count: 45, icon: '🔧' },
      { slug: 'business-apps', name: 'Business Apps', count: 32, icon: '💼' },
      { slug: 'marketing', name: 'Marketing', count: 28, icon: '📈' },
      { slug: 'analytics', name: 'Analytics', count: 23, icon: '📊' },
      { slug: 'communication', name: 'Communication', count: 18, icon: '💬' },
      { slug: 'security', name: 'Security', count: 15, icon: '🛡️' }
    ],
    priceTypes: [
      { type: 'free', label: 'Free', count: 67 },
      { type: 'freemium', label: 'Freemium', count: 43 },
      { type: 'paid', label: 'Paid', count: 89 },
      { type: 'subscription', label: 'Subscription', count: 112 }
    ],
    features: [
      { slug: 'api-integration', name: 'API Integration', count: 78 },
      { slug: 'webhooks', name: 'Webhooks', count: 56 },
      { slug: 'real-time', name: 'Real-time Data', count: 34 },
      { slug: 'automation', name: 'Automation', count: 67 },
      { slug: 'reporting', name: 'Reporting', count: 45 }
    ],
    ratings: [
      { rating: 5, count: 23, label: '5 stars' },
      { rating: 4, count: 45, label: '4 stars & up' },
      { rating: 3, count: 67, label: '3 stars & up' },
      { rating: 2, count: 78, label: '2 stars & up' }
    ],
    tags: [
      { slug: 'popular', name: 'Popular', count: 34 },
      { slug: 'trending', name: 'Trending', count: 23 },
      { slug: 'new', name: 'New', count: 12 }
    ]
  };

  // Enhanced handlers
  const handleSearch = (query: string) => {
    // In real implementation, trigger search API call
  };

  const handleFiltersChange = (filters: SearchFilters) => {
    setSearchFilters(filters);
    // In real implementation, trigger filtered search API call
  };

  const handleSubscribeApp = (app: App) => {
    setSelectedAppForSubscription(app);
    setShowSubscriptionModal(true);
  };

  const handleComparePlans = (app: App) => {
    setSelectedAppForComparison(app);
    setShowPlanComparisonModal(true);
  };

  const handleSubscribeToApp = async (app: App, planId?: string) => {
    try {
      const subscription = await appSubscriptionsApi.createSubscription(
        app.id, 
        planId || 'default',
        {}
      );
      
      
      // Refresh subscriptions list if on that tab
      if (subscriptionsRefreshRef.current) {
        subscriptionsRefreshRef.current();
      }
      
      return Promise.resolve();
    } catch (error: any) {
      console.error('Subscription creation failed:', error);
      throw new Error(error.response?.data?.error || 'Failed to create subscription');
    }
  };

  const handleViewAppDetails = (app: App) => {
    navigate(`/app/marketplace/apps/${app.id}`);
  };

  // Commented out until needed for My Apps tab
  // const handleManageApp = (app: App) => {
  //   navigate(`/app/marketplace/apps/${app.id}/manage`);
  // };

  const handleCategorySelect = (categorySlug: string) => {
    const newFilters = {
      ...searchFilters,
      categories: [categorySlug],
      page: 1
    };
    handleFiltersChange(newFilters);
  };

  const handleCategoryToggle = (categorySlug: string) => {
    const currentCategories = searchFilters.categories || [];
    const newCategories = currentCategories.includes(categorySlug)
      ? currentCategories.filter(cat => cat !== categorySlug)
      : [...currentCategories, categorySlug];
    
    const newFilters = {
      ...searchFilters,
      categories: newCategories,
      page: 1
    };
    handleFiltersChange(newFilters);
  };

  // Page actions
  const getBreadcrumbs = () => {
    const baseBreadcrumbs = [
      { label: 'Dashboard', href: '/app', icon: '🏠' },
      { label: 'Marketplace', href: '/app/marketplace', icon: '🏪' }
    ];
    
    const currentPath = location.pathname;
    if (currentPath.includes('/subscriptions')) {
      baseBreadcrumbs.push({ label: 'My Subscriptions', icon: '📱', href: '/app/marketplace/subscriptions' });
    } else if (currentPath.includes('/reviews')) {
      baseBreadcrumbs.push({ label: 'Reviews', icon: '⭐', href: '/app/marketplace/reviews' });
    } else if (currentPath.includes('/my-apps')) {
      baseBreadcrumbs.push({ label: 'My Apps', icon: '⚙️', href: '/app/marketplace/my-apps' });
    }
    
    return baseBreadcrumbs;
  };

  const pageActions = useMemo(() => {
    const baseActions: PageAction[] = [];

    if (activeTab === 'browse') {
      baseActions.push({
        id: 'toggle-sidebar',
        label: showSidebar ? 'Hide Filters' : 'Show Filters',
        onClick: () => setShowSidebar(!showSidebar),
        variant: 'outline' as const,
        icon: showSidebar ? Sidebar : Filter
      });
      baseActions.push({
        id: 'refresh',
        label: 'Refresh',
        onClick: refresh,
        variant: 'outline' as const,
        icon: RefreshCw
      });
    } else if (activeTab === 'subscriptions') {
      baseActions.push({
        id: 'refresh-subscriptions',
        label: 'Refresh',
        onClick: () => {
          if (subscriptionsRefreshRef.current) {
            subscriptionsRefreshRef.current();
          }
        },
        variant: 'outline' as const,
        icon: RefreshCw
      });
    } else if (activeTab === 'my-apps') {
      baseActions.push({
        id: 'create-app',
        label: 'Create App',
        onClick: () => setShowCreateModal(true),
        variant: 'primary' as const,
        icon: Plus,
        permission: 'apps.create'
      });
      baseActions.push({
        id: 'refresh-apps',
        label: 'Refresh',
        onClick: refreshApps,
        variant: 'outline' as const,
        icon: RefreshCw
      });
    }

    return baseActions;
  }, [activeTab, refresh, refreshApps, subscriptionsRefreshRef, showSidebar]);

  const handleSubscriptionAction = (action: string, subscriptionId: string) => {
  };

  // Commented out - functionality handled by pageActions
  // const handleCreateApp = () => {
  //   setShowCreateModal(true);
  // };

  const handleAppCreated = (app: App) => {
    setShowCreateModal(false);
    refreshApps();
    navigate(`/app/marketplace/apps/${app.id}`);
  };

  // Wrapper component for subscriptions with ref
  const SubscriptionsListWithRef: React.FC<{
    onSubscriptionAction: (action: string, subscriptionId: string) => void;
    refreshRef: React.MutableRefObject<(() => void) | null>;
  }> = ({ onSubscriptionAction, refreshRef }) => {
    const subscriptionsListRef = React.useRef<{ refresh: () => void } | null>(null);
    
    React.useEffect(() => {
      refreshRef.current = subscriptionsListRef.current?.refresh || null;
    }, [refreshRef]);
    
    return (
      <SubscriptionsList
        ref={subscriptionsListRef}
        onSubscriptionAction={onSubscriptionAction}
        showRefreshButton={false}
      />
    );
  };

  const tabs = [
    { 
      id: 'browse', 
      label: 'Browse Apps', 
      icon: '🏪',
      path: '/'
    },
    { 
      id: 'subscriptions', 
      label: 'My Subscriptions', 
      icon: '📱',
      path: '/subscriptions'
    },
    { 
      id: 'my-apps', 
      label: 'My Apps', 
      icon: '⚙️',
      path: '/my-apps'
    },
    { 
      id: 'reviews', 
      label: 'Reviews', 
      icon: '⭐',
      path: '/reviews'
    }
  ];

  return (
    <PageContainer
      title="App Marketplace"
      breadcrumbs={getBreadcrumbs()}
      actions={pageActions}
    >
      <TabContainer
        tabs={tabs}
        basePath="/app/marketplace"
        variant="underline"
        className="space-y-6"
      >
        <TabPanel tabId="browse" activeTab={activeTab}>
          <div className="space-y-6">
            {/* Enhanced Search Interface */}
            <MarketplaceSearch
              filters={searchFilters}
              facets={searchFacets}
              onFiltersChange={handleFiltersChange}
              onSearch={handleSearch}
              isLoading={loading}
              resultCount={apps.length}
            />

            <div className="flex gap-6">
              {/* Sidebar with Category Navigation */}
              {showSidebar && (
                <div className="w-80 flex-shrink-0">
                  <CategoryNavigation
                    categories={searchFacets.categories}
                    selectedCategories={searchFilters.categories || []}
                    onCategorySelect={handleCategorySelect}
                    onCategoryToggle={handleCategoryToggle}
                  />
                </div>
              )}

              {/* Main Content Area */}
              <div className="flex-1">
                {loading ? (
                  <div className="flex justify-center py-12">
                    <LoadingSpinner size="lg" />
                  </div>
                ) : error ? (
                  <div className="text-center py-12">
                    <div className="text-theme-error mb-4">⚠️ {error}</div>
                    <Button onClick={refresh} variant="primary">
                      Try Again
                    </Button>
                  </div>
                ) : apps.length === 0 ? (
                  <div className="text-center py-12">
                    <div className="text-6xl mb-4">📱</div>
                    <h3 className="text-xl font-semibold text-theme-primary mb-2">No apps found</h3>
                    <p className="text-theme-secondary">
                      Try adjusting your search criteria or browse different categories.
                    </p>
                  </div>
                ) : (
                  <div className="space-y-4">
                    {/* Results Grid/List */}
                    <div className={
                      searchFilters.viewMode === 'grid'
                        ? 'grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6'
                        : searchFilters.viewMode === 'list'
                        ? 'space-y-4'
                        : 'space-y-2'
                    }>
                      {apps.map((app) => (
                        <AppCardEnhanced
                          key={app.id}
                          app={app}
                          viewMode={searchFilters.viewMode as ViewMode}
                          showSubscription={true}
                          onSubscribe={handleSubscribeApp}
                          onViewDetails={handleViewAppDetails}
                          onComparePlans={handleComparePlans}
                        />
                      ))}
                    </div>

                    {/* Pagination */}
                    {pagination.total_pages > 1 && (
                      <div className="flex justify-center pt-8">
                        <div className="flex items-center space-x-2">
                          <Button
                            variant="outline"
                            size="sm"
                            disabled={pagination.current_page <= 1}
                            onClick={() => handleFiltersChange({
                              ...searchFilters,
                              page: Math.max(1, (searchFilters.page || 1) - 1)
                            })}
                          >
                            Previous
                          </Button>
                          
                          <span className="text-sm text-theme-secondary px-4">
                            Page {pagination.current_page} of {pagination.total_pages}
                          </span>
                          
                          <Button
                            variant="outline"
                            size="sm"
                            disabled={pagination.current_page >= pagination.total_pages}
                            onClick={() => handleFiltersChange({
                              ...searchFilters,
                              page: Math.min(pagination.total_pages, (searchFilters.page || 1) + 1)
                            })}
                          >
                            Next
                          </Button>
                        </div>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          </div>
        </TabPanel>

        <TabPanel tabId="subscriptions" activeTab={activeTab}>
          <SubscriptionsListWithRef
            onSubscriptionAction={handleSubscriptionAction}
            refreshRef={subscriptionsRefreshRef}
          />
        </TabPanel>

        <TabPanel tabId="my-apps" activeTab={activeTab}>
          <div className="space-y-6">
            {/* Existing AppsList component for now */}
            <div className="text-center py-12">
              <div className="text-6xl mb-4">⚙️</div>
              <h3 className="text-xl font-semibold text-theme-primary mb-2">My Apps</h3>
              <p className="text-theme-secondary">
                Manage your published apps and create new ones.
              </p>
            </div>
          </div>
        </TabPanel>

        <TabPanel tabId="reviews" activeTab={activeTab}>
          <div className="text-center py-12">
            <div className="text-6xl mb-4">⭐</div>
            <h3 className="text-xl font-semibold text-theme-primary mb-2">App Reviews</h3>
            <p className="text-theme-secondary">
              Review and rate marketplace apps you've used.
            </p>
            <p className="text-sm text-theme-tertiary mt-2">
              Coming soon - Rate apps and share your experience with the community.
            </p>
          </div>
        </TabPanel>
      </TabContainer>

      {/* Modals */}
      {showCreateModal && (
        <CreateAppModal
          isOpen={showCreateModal}
          onClose={() => setShowCreateModal(false)}
          onSuccess={handleAppCreated}
        />
      )}

      {showSubscriptionModal && (
        <AppSubscriptionModal
          isOpen={showSubscriptionModal}
          onClose={() => {
            setShowSubscriptionModal(false);
            setSelectedAppForSubscription(null);
          }}
          app={selectedAppForSubscription}
          onSubscribe={handleSubscribeToApp}
        />
      )}

      {showPlanComparisonModal && (
        <PlanComparisonModal
          isOpen={showPlanComparisonModal}
          onClose={() => {
            setShowPlanComparisonModal(false);
            setSelectedAppForComparison(null);
          }}
          app={selectedAppForComparison}
          onSelectPlan={async (planId: string) => {
            if (selectedAppForComparison) {
              await handleSubscribeToApp(selectedAppForComparison, planId);
            }
          }}
        />
      )}
    </PageContainer>
  );
};