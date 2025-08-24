import React, { useState, useEffect, useRef } from 'react';
import { 
  Plus, 
  RefreshCw, 
  Search,
  Filter,
  Eye,
  Trash2,
  CheckCircle,
  XCircle,
  AlertTriangle,
  Star,
  TrendingUp,
  Download
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotification } from '@/shared/hooks/useNotification';
import { appsApi, marketplaceListingsApi } from '@/features/marketplace/services/marketplaceApi';
import type { App, MarketplaceListing } from '@/features/marketplace/types';

interface AdminMarketplacePageProps {
  className?: string;
}

export const AdminMarketplacePage: React.FC<AdminMarketplacePageProps> = ({ className = '' }) => {
AdminMarketplacePage.displayName = 'AdminMarketplacePage';
  const [activeTab, setActiveTab] = useState<'apps' | 'listings' | 'reviews' | 'analytics'>('apps');
  const [apps, setApps] = useState<App[]>([]);
  const [listings, setListings] = useState<MarketplaceListing[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedApp, setSelectedApp] = useState<App | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const { showNotification } = useNotification();

  // Prevent duplicate API calls in StrictMode by tracking initial load
  const hasLoadedRef = useRef(false);
  const currentTabRef = useRef<'apps' | 'listings' | 'reviews' | 'analytics'>('apps');

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Administration', href: '/app/admin', icon: '⚙️' },
    { label: 'Marketplace', icon: '🏪' }
  ];

  const getPageActions = (): PageAction[] => {
    const baseActions: PageAction[] = [
      { 
        id: 'refresh', 
        label: 'Refresh', 
        onClick: loadData, 
        variant: 'secondary', 
        icon: RefreshCw, 
        disabled: loading 
      },
      {
        id: 'export',
        label: 'Export Report',
        onClick: handleExportReport,
        variant: 'secondary',
        icon: Download,
        permission: 'admin.marketplace.export'
      }
    ];

    if (activeTab === 'apps') {
      baseActions.unshift({
        id: 'create-app',
        label: 'Create App',
        onClick: () => setShowCreateModal(true),
        variant: 'primary',
        icon: Plus,
        permission: 'admin.marketplace.manage'
      });
    }

    return baseActions;
  };

  const loadData = async () => {
    setLoading(true);
    try {
      if (activeTab === 'apps') {
        const response = await appsApi.getApps({ page: 1, per_page: 50 });
        setApps(response.data || []);
      } else if (activeTab === 'listings') {
        const response = await marketplaceListingsApi.getMarketplaceListings({ page: 1, per_page: 50 });
        setListings(response.data || []);
      }
    } catch (error: any) {
      showNotification(error.response?.data?.error || 'Failed to load data', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleExportReport = () => {
    // TODO: Implement export functionality
    showNotification('Export functionality coming soon', 'info');
  };

  const handleAppAction = async (appId: string, action: 'approve' | 'reject' | 'publish' | 'unpublish' | 'delete') => {
    try {
      setLoading(true);
      
      switch (action) {
        case 'publish':
          await appsApi.publishApp(appId);
          showNotification('App published successfully', 'success');
          break;
        case 'unpublish':
          await appsApi.unpublishApp(appId);
          showNotification('App unpublished successfully', 'success');
          break;
        case 'delete':
          await appsApi.deleteApp(appId);
          showNotification('App deleted successfully', 'success');
          break;
        default:
          showNotification(`${action} functionality coming soon`, 'info');
          return;
      }
      
      await loadData();
    } catch (error: any) {
      showNotification(error.response?.data?.error || `Failed to ${action} app`, 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleListingAction = async (appId: string, action: 'approve' | 'reject' | 'feature' | 'unfeature') => {
    try {
      setLoading(true);
      
      switch (action) {
        case 'approve':
          await marketplaceListingsApi.approveListing(appId);
          showNotification('Listing approved successfully', 'success');
          break;
        case 'reject':
          await marketplaceListingsApi.rejectListing(appId, 'Admin review required');
          showNotification('Listing rejected successfully', 'success');
          break;
        case 'feature':
          await marketplaceListingsApi.featureListing(appId);
          showNotification('Listing featured successfully', 'success');
          break;
        case 'unfeature':
          await marketplaceListingsApi.unfeatureListing(appId);
          showNotification('Listing unfeatured successfully', 'success');
          break;
      }
      
      await loadData();
    } catch (error: any) {
      showNotification(error.response?.data?.error || `Failed to ${action} listing`, 'error');
    } finally {
      setLoading(false);
    }
  };

  const getStatusBadgeVariant = (status: string) => {
    switch (status) {
      case 'published':
      case 'approved':
        return 'success';
      case 'draft':
      case 'pending_review':
        return 'warning';
      case 'rejected':
      case 'suspended':
        return 'danger';
      default:
        return 'default';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'published':
      case 'approved':
        return <CheckCircle className="w-4 h-4" />;
      case 'rejected':
      case 'suspended':
        return <XCircle className="w-4 h-4" />;
      case 'pending_review':
        return <AlertTriangle className="w-4 h-4" />;
      default:
        return null;
    }
  };

  const filteredApps = apps.filter(app => 
    app.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    app.description?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const filteredListings = listings.filter(listing => 
    listing.app.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    listing.short_description?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  useEffect(() => {
    // Prevent duplicate calls in StrictMode: only load if tab changed or first load
    if (!hasLoadedRef.current || currentTabRef.current !== activeTab) {
      hasLoadedRef.current = true;
      currentTabRef.current = activeTab;
      loadData();
    }
  }, [activeTab]);

  const tabs = [
    { id: 'apps' as const, label: 'Apps', icon: '📱', count: apps.length },
    { id: 'listings' as const, label: 'Listings', icon: '🏪', count: listings.length },
    { id: 'reviews' as const, label: 'Reviews', icon: '⭐', count: 0 },
    { id: 'analytics' as const, label: 'Analytics', icon: '📊', count: 0 }
  ];

  const renderAppsTab = () => (
    <div className="space-y-6">
      {/* Search and Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-secondary w-4 h-4" />
          <input
            type="text"
            placeholder="Search apps..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
          />
        </div>
        <Button variant="outline" size="sm" className="flex items-center space-x-2">
          <Filter className="w-4 h-4" />
          <span>Filters</span>
        </Button>
      </div>

      {/* Apps List */}
      <div className="grid gap-4">
        {loading && <div className="text-center py-8 text-theme-secondary">Loading apps...</div>}
        {!loading && filteredApps.length === 0 && (
          <div className="text-center py-8 text-theme-secondary">
            {searchTerm ? 'No apps match your search.' : 'No apps found.'}
          </div>
        )}
        {filteredApps.map((app) => (
          <Card key={app.id} className="p-6">
            <div className="flex items-start justify-between">
              <div className="flex items-center space-x-4">
                {app.icon ? (
                  <img 
                    src={app.icon} 
                    alt={app.name} 
                    className="w-12 h-12 rounded-lg object-cover"
                  />
                ) : (
                  <div className="w-12 h-12 rounded-lg bg-theme-interactive-primary/10 flex items-center justify-center">
                    <span className="text-xl">{app.name.charAt(0)}</span>
                  </div>
                )}
                <div className="flex-1">
                  <h3 className="text-lg font-semibold text-theme-primary">{app.name}</h3>
                  <p className="text-sm text-theme-secondary">{app.description}</p>
                  <div className="flex items-center space-x-4 mt-2">
                    <Badge variant={getStatusBadgeVariant(app.status)} className="flex items-center space-x-1">
                      {getStatusIcon(app.status)}
                      <span className="capitalize">{app.status}</span>
                    </Badge>
                    <span className="text-sm text-theme-secondary">
                      Version {app.version || '1.0.0'}
                    </span>
                    <span className="text-sm text-theme-secondary">
                      Created {new Date(app.created_at).toLocaleDateString()}
                    </span>
                  </div>
                </div>
              </div>
              
              <div className="flex items-center space-x-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setSelectedApp(app);
                    setShowDetails(true);
                  }}
                  title="View Details"
                >
                  <Eye className="w-4 h-4" />
                </Button>
                
                {app.status === 'draft' && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleAppAction(app.id, 'publish')}
                    disabled={loading}
                    title="Publish App"
                  >
                    <CheckCircle className="w-4 h-4" />
                  </Button>
                )}
                
                {app.status === 'published' && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleAppAction(app.id, 'unpublish')}
                    disabled={loading}
                    title="Unpublish App"
                  >
                    <XCircle className="w-4 h-4" />
                  </Button>
                )}
                
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => handleAppAction(app.id, 'delete')}
                  disabled={loading}
                  title="Delete App"
                  className="text-theme-error hover:text-theme-error"
                >
                  <Trash2 className="w-4 h-4" />
                </Button>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );

  const renderListingsTab = () => (
    <div className="space-y-6">
      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-secondary w-4 h-4" />
        <input
          type="text"
          placeholder="Search listings..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
        />
      </div>

      {/* Listings */}
      <div className="grid gap-4">
        {loading && <div className="text-center py-8 text-theme-secondary">Loading listings...</div>}
        {!loading && filteredListings.length === 0 && (
          <div className="text-center py-8 text-theme-secondary">
            {searchTerm ? 'No listings match your search.' : 'No marketplace listings found.'}
          </div>
        )}
        {filteredListings.map((listing) => (
          <Card key={listing.id} className="p-6">
            <div className="flex items-start justify-between">
              <div className="flex items-center space-x-4">
                <div className="w-12 h-12 rounded-lg bg-theme-interactive-primary/10 flex items-center justify-center">
                  <span className="text-xl">{listing.app.name.charAt(0)}</span>
                </div>
                <div className="flex-1">
                  <h3 className="text-lg font-semibold text-theme-primary">{listing.app.name}</h3>
                  <p className="text-sm text-theme-secondary">{listing.short_description}</p>
                  <div className="flex items-center space-x-4 mt-2">
                    <Badge variant={getStatusBadgeVariant(listing.review_status)} className="flex items-center space-x-1">
                      {getStatusIcon(listing.review_status)}
                      <span className="capitalize">{listing.review_status}</span>
                    </Badge>
                    {listing.featured && (
                      <Badge variant="warning" className="flex items-center space-x-1">
                        <Star className="w-3 h-3" />
                        <span>Featured</span>
                      </Badge>
                    )}
                    <span className="text-sm text-theme-secondary">
                      Category: {listing.category}
                    </span>
                  </div>
                </div>
              </div>
              
              <div className="flex items-center space-x-2">
                {listing.review_status === 'pending' && (
                  <>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleListingAction(listing.id, 'approve')}
                      disabled={loading}
                      title="Approve Listing"
                    >
                      <CheckCircle className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleListingAction(listing.id, 'reject')}
                      disabled={loading}
                      title="Reject Listing"
                    >
                      <XCircle className="w-4 h-4" />
                    </Button>
                  </>
                )}
                
                {listing.review_status === 'approved' && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleListingAction(listing.id, listing.featured ? 'unfeature' : 'feature')}
                    disabled={loading}
                    title={listing.featured ? 'Remove Featured' : 'Make Featured'}
                  >
                    <Star className={`w-4 h-4 ${listing.featured ? 'fill-current' : ''}`} />
                  </Button>
                )}
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );

  const renderComingSoonTab = (tabName: string) => (
    <div className="text-center py-12">
      <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-theme-interactive-primary/10 flex items-center justify-center">
        <TrendingUp className="w-8 h-8 text-theme-interactive-primary" />
      </div>
      <h3 className="text-lg font-semibold text-theme-primary mb-2">{tabName} Coming Soon</h3>
      <p className="text-theme-secondary">
        This section will provide detailed {tabName.toLowerCase()} management capabilities.
      </p>
    </div>
  );

  return (
    <PageContainer
      title="Marketplace Management"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
      className={className}
    >
      {/* Tabs */}
      <div className="border-b border-theme mb-6">
        <div className="flex space-x-8 -mb-px overflow-x-auto scrollbar-hide">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm ${
                activeTab === tab.id
                  ? 'border-theme-link text-theme-link'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
              }`}
            >
              <span className="text-base">{tab.icon}</span>
              <span>{tab.label}</span>
              {tab.count > 0 && (
                <Badge variant="secondary" className="ml-1">{tab.count}</Badge>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Tab Content */}
      {activeTab === 'apps' && renderAppsTab()}
      {activeTab === 'listings' && renderListingsTab()}
      {activeTab === 'reviews' && renderComingSoonTab('Reviews')}
      {activeTab === 'analytics' && renderComingSoonTab('Analytics')}

      {/* App Details Modal */}
      {showDetails && selectedApp && (
        <Modal
          isOpen={showDetails}
          onClose={() => setShowDetails(false)}
          title="App Details"
          maxWidth="lg"
        >
          <div className="space-y-4">
            <div className="flex items-center space-x-4">
              {selectedApp.icon ? (
                <img 
                  src={selectedApp.icon} 
                  alt={selectedApp.name} 
                  className="w-16 h-16 rounded-lg object-cover"
                />
              ) : (
                <div className="w-16 h-16 rounded-lg bg-theme-interactive-primary/10 flex items-center justify-center">
                  <span className="text-2xl">{selectedApp.name.charAt(0)}</span>
                </div>
              )}
              <div>
                <h3 className="text-xl font-semibold text-theme-primary">{selectedApp.name}</h3>
                <p className="text-theme-secondary">Version {selectedApp.version || '1.0.0'}</p>
              </div>
            </div>
            
            <div className="space-y-3">
              <div>
                <label className="text-sm font-medium text-theme-primary">Description</label>
                <p className="text-theme-secondary">{selectedApp.description || 'No description provided'}</p>
              </div>
              
              <div>
                <label className="text-sm font-medium text-theme-primary">Status</label>
                <div className="mt-1">
                  <Badge variant={getStatusBadgeVariant(selectedApp.status)} className="flex items-center space-x-1 w-fit">
                    {getStatusIcon(selectedApp.status)}
                    <span className="capitalize">{selectedApp.status}</span>
                  </Badge>
                </div>
              </div>
              
              <div>
                <label className="text-sm font-medium text-theme-primary">Created</label>
                <p className="text-theme-secondary">{new Date(selectedApp.created_at).toLocaleDateString()}</p>
              </div>
              
              <div>
                <label className="text-sm font-medium text-theme-primary">Last Updated</label>
                <p className="text-theme-secondary">{new Date(selectedApp.updated_at).toLocaleDateString()}</p>
              </div>
            </div>
            
            <div className="flex justify-end space-x-3 pt-4 border-t border-theme">
              <Button variant="outline" onClick={() => setShowDetails(false)}>
                Close
              </Button>
              <Button 
                variant="primary"
                onClick={() => {
                  // TODO: Navigate to app edit page
                  showNotification('App editing coming soon', 'info');
                }}
              >
                Edit App
              </Button>
            </div>
          </div>
        </Modal>
      )}

      {/* Create App Modal Placeholder */}
      {showCreateModal && (
        <Modal
          isOpen={showCreateModal}
          onClose={() => setShowCreateModal(false)}
          title="Create New App"
          maxWidth="md"
        >
          <div className="text-center py-8">
            <p className="text-theme-secondary mb-4">App creation functionality will be implemented soon.</p>
            <Button variant="outline" onClick={() => setShowCreateModal(false)}>
              Close
            </Button>
          </div>
        </Modal>
      )}
    </PageContainer>
  );
};

export default AdminMarketplacePage;