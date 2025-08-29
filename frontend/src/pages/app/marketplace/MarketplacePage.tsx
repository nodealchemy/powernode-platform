import React, { useState, useRef, useMemo } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { AppCard } from '@/features/marketplace/components/apps/AppCard';
import { AppsList } from '@/features/marketplace/components/apps/AppsList';
import { CreateAppModal } from '@/features/marketplace/components/apps/CreateAppModal';
import { AppSubscriptionModal } from '@/features/marketplace/components/apps/AppSubscriptionModal';
import { SubscriptionsList } from '@/features/marketplace/components/SubscriptionsList';
import { useMarketplaceListings } from '@/features/marketplace/hooks/useMarketplace';
import { useApps } from '@/features/marketplace/hooks/useApps';
import { appSubscriptionsApi } from '@/features/marketplace/services/appSubscriptionsApi';
import { App, MarketplaceFilters, AppFilters } from '@/features/marketplace/types';
import { RefreshCw, Plus } from 'lucide-react';

export const MarketplacePage: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { user } = useSelector((state: RootState) => state.auth);
  
  const [filters] = useState<MarketplaceFilters>({ 
    page: 1, 
    per_page: 20,
    status: 'approved' 
  });
  
  const [appFilters] = useState<AppFilters>({ 
    page: 1, 
    per_page: 20 
  });
  
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showSubscriptionModal, setShowSubscriptionModal] = useState(false);
  const [selectedAppForSubscription, setSelectedAppForSubscription] = useState<App | null>(null);
  const [expandedAppId, setExpandedAppId] = useState<string | null>(null);
  
  // Create ref to store subscriptions refresh function
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

  const { 
    listings, 
    loading, 
    error, 
    refresh 
  } = useMarketplaceListings(filters);

  const { 
    refresh: refreshApps 
  } = useApps(appFilters);

  // Helper function to determine ownership
  const isUserAppOwner = (app: App, activeTabContext: string): boolean => {
    // For "My Apps" tab, user is always the owner
    if (activeTabContext === 'my-apps') {
      return true;
    }
    
    // For other tabs (browse, subscriptions, reviews), check if user can manage
    // In a real implementation, this would check if user has ownership or management permissions for the app
    // For now, we'll assume users don't own apps from the marketplace browse view
    if (activeTabContext === 'browse') {
      return false;
    }
    
    // For subscriptions and reviews, users don't own the apps but may have subscriptions
    return false;
  };

  // Convert listings to apps for the AppsList component
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

  const handleSubscribeApp = (app: App) => {
    setSelectedAppForSubscription(app);
    setShowSubscriptionModal(true);
  };

  const handleSubscribeToApp = async (app: App, planId?: string) => {
    try {
      // For now, we'll create a basic subscription since the modal uses mock plan IDs
      // In a real implementation, you'd get actual app plan IDs from the app data
      const subscription = await appSubscriptionsApi.createSubscription(
        app.id, 
        planId || 'default', // Use the selected plan ID or default
        {} // Empty configuration for now
      );
      
      
      // Refresh subscriptions list if on that tab
      if (subscriptionsRefreshRef.current) {
        subscriptionsRefreshRef.current();
      }
      
      return Promise.resolve();
    } catch (error: unknown) {
      // Re-throw the error so the modal can handle it
      let errorMessage = 'Failed to create subscription';
      if (error && typeof error === 'object' && 'response' in error && error.response && 
          typeof error.response === 'object' && 'data' in error.response && error.response.data &&
          typeof error.response.data === 'object' && 'error' in error.response.data) {
        errorMessage = (error.response.data as any).error || errorMessage;
      }
      throw new Error(errorMessage);
    }
  };

  const handleToggleExpansion = (app: App) => {
    // Toggle expansion for the clicked app
    setExpandedAppId(expandedAppId === app.id ? null : app.id);
  };

  const handleManageApp = (app: App) => {
    // Navigate to app management page for owners
    navigate(`/app/marketplace/apps/${app.id}`);
  };


  const getBreadcrumbs = () => {
    const baseBreadcrumbs = [
      { label: 'Dashboard', href: '/app', icon: '🏠' },
      { label: 'Marketplace', href: '/app/marketplace', icon: '🏪' }
    ];
    
    // Add tab-specific breadcrumb if not on main tab
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

    // Add tab-specific actions
    if (activeTab === 'browse') {
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
  }, [activeTab, refresh, refreshApps, subscriptionsRefreshRef]);

  const handleSubscriptionAction = (action: string, subscriptionId: string) => {
    
    switch (action) {
      case 'view-usage':
        break;
      case 'view-analytics':
        break;
      case 'configure':
        break;
      default:
        break;
    }
  };

  const handleCreateApp = () => {
    setShowCreateModal(true);
  };

  const handleAppCreated = (app: unknown) => {
    setShowCreateModal(false);
    refreshApps();
    // Navigate to the new app's management page if app has an ID
    if (app && typeof app === 'object' && 'id' in app) {
      navigate(`/app/marketplace/apps/${(app as any).id}`);
    }
  };

  // Wrapper component to expose refresh function to parent
  const SubscriptionsListWithRef: React.FC<{
    onSubscriptionAction: (action: string, subscriptionId: string) => void;
    refreshRef: React.MutableRefObject<(() => void) | null>;
  }> = ({ onSubscriptionAction, refreshRef }) => {
    // Create a ref to capture the refresh function from SubscriptionsList
    const subscriptionsListRef = React.useRef<{ refresh: () => void } | null>(null);
    
    // Expose refresh function to parent via ref
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
            {/* Welcome Banner */}
            <div className="bg-gradient-to-r from-theme-interactive-primary to-theme-interactive-secondary text-white rounded-lg p-4 sm:p-6">
              <h2 className="text-xl sm:text-2xl font-bold mb-2">Welcome to the App Marketplace</h2>
              <p className="text-white/90 mb-4 text-sm sm:text-base">
                Discover powerful apps and integrations to extend your platform capabilities
              </p>
              <div className="flex flex-col sm:flex-row items-start sm:items-center space-y-2 sm:space-y-0 sm:space-x-6 text-xs sm:text-sm">
                <div className="flex items-center space-x-2">
                  <span className="w-2 h-2 bg-white rounded-full"></span>
                  <span>Verified Apps</span>
                </div>
                <div className="flex items-center space-x-2">
                  <span className="w-2 h-2 bg-white rounded-full"></span>
                  <span>Easy Installation</span>
                </div>
                <div className="flex items-center space-x-2">
                  <span className="w-2 h-2 bg-white rounded-full"></span>
                  <span>API Integration</span>
                </div>
              </div>
            </div>

            {loading ? (
              <div className="flex justify-center py-12">
                <div className="animate-spin rounded-full h-32 w-32 border-b-2 border-theme-interactive-primary"></div>
              </div>
            ) : error ? (
              <div className="text-center py-12">
                <div className="text-theme-error mb-4">⚠️ {error}</div>
                <button onClick={refresh} className="btn-theme btn-theme-primary">
                  Try Again
                </button>
              </div>
            ) : apps.length === 0 ? (
              <div className="text-center py-12">
                <div className="text-6xl mb-4">📱</div>
                <h3 className="text-xl font-semibold text-theme-primary mb-2">No apps available</h3>
                <p className="text-theme-secondary">
                  Check back later for new apps in the marketplace.
                </p>
              </div>
            ) : (
              <div className="space-y-6">
                {/* Show expanded app first if any */}
                {expandedAppId && apps.find(app => app.id === expandedAppId) && (
                  <div className="w-full">
                    <AppCard
                      app={apps.find(app => app.id === expandedAppId)!}
                      isOwner={isUserAppOwner(apps.find(app => app.id === expandedAppId)!, activeTab)}
                      showSubscription={activeTab === 'browse'}
                      onSubscribe={handleSubscribeApp}
                      onManage={handleManageApp}
                      expanded={true}
                      onToggleExpansion={handleToggleExpansion}
                    />
                  </div>
                )}

                {/* Show other apps in grid */}
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
                  {apps.filter(app => app.id !== expandedAppId).map((app) => (
                    <AppCard
                      key={app.id}
                      app={app}
                      isOwner={isUserAppOwner(app, activeTab)}
                      showSubscription={activeTab === 'browse'}
                      onSubscribe={handleSubscribeApp}
                      onManage={handleManageApp}
                      expanded={false}
                      onToggleExpansion={handleToggleExpansion}
                    />
                  ))}
                </div>
              </div>
            )}
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
            <AppsList
              onCreateApp={handleCreateApp}
              onViewApp={handleManageApp}
              filters={appFilters}
              showCreateButton={false}
            />
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
    </PageContainer>
  );
};