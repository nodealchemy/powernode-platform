import React, { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EndpointCard } from '@/features/marketplace/components/endpoints/EndpointCard';
import { WebhooksList } from '@/features/marketplace/components/webhooks/WebhooksList';
import { useApp } from '@/features/marketplace/hooks/useApps';
import { useAppEndpoints } from '@/features/marketplace/hooks/useEndpoints';
import { useAppWebhooks } from '@/features/marketplace/hooks/useWebhooks';
import { useAppSubscriptions } from '@/features/marketplace/hooks/useAppSubscriptions';
import { AppStatus } from '@/features/marketplace/types';
import { Settings, Globe, Calendar, Code, Webhook, RefreshCw, Upload, EyeOff } from 'lucide-react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { appsApi } from '@/features/marketplace/services/marketplaceApi';

export const AppDetailPage: React.FC = () => {
  const { appId } = useParams<{ appId: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const [activeTab, setActiveTab] = useState<'overview' | 'endpoints' | 'webhooks' | 'analytics'>('overview');
  const [publishing, setPublishing] = useState(false);

  // Always call hooks at the top level - use empty string as fallback to avoid conditional calls
  const { app, loading, error, refresh } = useApp(appId || '');
  const { endpoints, loading: endpointsLoading } = useAppEndpoints(appId || '', {});
  const { webhooks, refresh: refreshWebhooks } = useAppWebhooks(appId || '', {});
  const { subscriptions } = useAppSubscriptions(undefined, false);

  // Handle missing appId in render logic
  if (!appId) {
    return (
      <PageContainer title="App Not Found" description="The requested app could not be found.">
        <div className="text-center py-12">
          <h3 className="text-lg font-medium text-theme-primary mb-2">App Not Found</h3>
          <p className="text-theme-secondary mb-4">The app you're looking for doesn't exist or you don't have access to it.</p>
          <Button onClick={() => navigate('/app/marketplace')}>Back to Marketplace</Button>
        </div>
      </PageContainer>
    );
  }

  // Check if user is already subscribed to this app
  const existingSubscription = subscriptions.find(sub => sub.app.id === appId && sub.status === 'active');

  const handleEditApp = () => {
    navigate(`/app/marketplace/apps/${appId}/edit`);
  };

  const handlePublish = async () => {
    if (!appId) return;
    try {
      setPublishing(true);
      await appsApi.publishApp(appId);
      showNotification('App published successfully', 'success');
      refresh();
    } catch (error) {
      showNotification(error instanceof Error ? error.message : 'Failed to publish app', 'error');
    } finally {
      setPublishing(false);
    }
  };

  const handleUnpublish = async () => {
    if (!appId) return;
    try {
      setPublishing(true);
      await appsApi.unpublishApp(appId);
      showNotification('App unpublished successfully', 'success');
      refresh();
    } catch (error) {
      showNotification(error instanceof Error ? error.message : 'Failed to unpublish app', 'error');
    } finally {
      setPublishing(false);
    }
  };

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Marketplace', href: '/app/marketplace', icon: '🏪' },
    { label: 'My Apps', href: '/app/marketplace/my-apps', icon: '📱' },
    { label: app?.name || 'App', icon: '📄' }
  ];


  const handleWebhookAction = (action: string, _webhookId: string) => {
    // Refresh webhooks when needed
    if (['create', 'update', 'delete', 'toggle-status'].includes(action)) {
      refreshWebhooks();
    }
  };

  const getPageActions = () => {
    const actions = [];

    // Show install/manage subscription actions for published apps
    if (app?.status === 'published') {
      if (existingSubscription) {
        // Show subscription management actions
        actions.push({
          id: 'manage-subscription',
          label: 'Manage Subscription',
          onClick: () => navigate('/app/subscriptions'),
          variant: 'primary' as const,
          icon: Settings
        });
      }
    }

    // Show edit action for own apps
    actions.push({
      id: 'edit',
      label: 'Edit App',
      onClick: handleEditApp,
      variant: 'outline' as const,
      icon: Settings,
      permission: 'apps.update'
    });
    
    actions.push({
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'secondary' as const,
      icon: RefreshCw
    });

    if (app?.status === 'draft' || app?.status === 'inactive') {
      actions.unshift({
        id: 'publish',
        label: publishing ? 'Publishing...' : 'Publish App',
        onClick: handlePublish,
        variant: 'outline' as const,
        icon: Upload,
        permission: 'apps.publish',
        disabled: publishing
      });
    } else if (app?.status === 'published') {
      actions.unshift({
        id: 'unpublish',
        label: publishing ? 'Unpublishing...' : 'Unpublish',
        onClick: handleUnpublish,
        variant: 'outline' as const,
        icon: EyeOff,
        permission: 'apps.publish',
        disabled: publishing
      });
    }

    return actions;
  };

  const getStatusBadgeVariant = (status: AppStatus): 'success' | 'warning' | 'danger' | 'secondary' => {
    switch (status) {
      case 'published': return 'success';
      case 'draft': return 'secondary';
      case 'under_review': return 'warning';
      case 'inactive': return 'danger';
      default: return 'secondary';
    }
  };

  const formatStatus = (status: string) => {
    return status.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase());
  };

  const tabs = [
    { id: 'overview', label: 'Overview', icon: '📊' },
    { id: 'endpoints', label: 'API Endpoints', icon: '📡', count: endpoints.length },
    { id: 'webhooks', label: 'Webhooks', icon: '🔗', count: webhooks.length },
    { id: 'analytics', label: 'Analytics', icon: '📈' }
  ] as const;

  if (loading) {
    return (
      <PageContainer title="Loading..." breadcrumbs={getBreadcrumbs()}>
        <div className="flex justify-center py-12">
          <LoadingSpinner />
        </div>
      </PageContainer>
    );
  }

  if (error || !app) {
    return (
      <PageContainer title="App Not Found" breadcrumbs={getBreadcrumbs()}>
        <div className="text-center py-12">
          <div className="text-theme-error mb-4">⚠️ {error || 'App not found'}</div>
          <Button onClick={() => navigate('/app/marketplace/my-apps')} variant="primary">
            Back to My Apps
          </Button>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={app.name}
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      <div className="space-y-6">
        {/* App Header */}
        <Card className="p-6">
          <div className="flex items-start space-x-4">
            <div className="w-16 h-16 bg-theme-interactive-primary rounded-xl flex items-center justify-center text-white text-2xl">
              {app.icon || '📱'}
            </div>
            
            <div className="flex-1">
              <div className="flex items-center space-x-3 mb-2">
                <h1 className="text-2xl font-bold text-theme-primary">{app.name}</h1>
                <Badge variant={getStatusBadgeVariant(app.status)}>
                  {formatStatus(app.status)}
                </Badge>
                <Badge variant="outline">v{app.version}</Badge>
              </div>
              
              <p className="text-theme-secondary mb-4">
                {app.description}
              </p>
              
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                <div className="flex items-center space-x-2">
                  <Globe className="w-4 h-4 text-theme-tertiary" />
                  <span className="text-theme-secondary">{app.category}</span>
                </div>
                <div className="flex items-center space-x-2">
                  <Calendar className="w-4 h-4 text-theme-tertiary" />
                  <span className="text-theme-secondary">
                    Updated {new Date(app.updated_at).toLocaleDateString()}
                  </span>
                </div>
                <div className="flex items-center space-x-2">
                  <Code className="w-4 h-4 text-theme-tertiary" />
                  <span className="text-theme-secondary">{endpoints.length} endpoints</span>
                </div>
                <div className="flex items-center space-x-2">
                  <Webhook className="w-4 h-4 text-theme-tertiary" />
                  <span className="text-theme-secondary">{webhooks.length} webhooks</span>
                </div>
              </div>
            </div>
          </div>
        </Card>

        {/* Tabs */}
        <div className="border-b border-theme">
          <div className="flex space-x-8 -mb-px overflow-x-auto scrollbar-hide">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm ${
                  activeTab === tab.id
                    ? 'border-theme-link text-theme-link'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary'
                }`}
              >
                <span className="text-base">{tab.icon}</span>
                <span>{tab.label}</span>
                {'count' in tab && tab.count !== undefined && (
                  <Badge variant="outline" className="text-xs">
                    {tab.count}
                  </Badge>
                )}
              </button>
            ))}
          </div>
        </div>

        {/* Tab Content */}
        <div className="space-y-6">
          {activeTab === 'overview' && (
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <div className="lg:col-span-2 space-y-6">
                <Card className="p-6">
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Description</h3>
                  <div className="prose prose-sm text-theme-secondary">
                    {app.description}
                  </div>
                </Card>

                {app.tags && app.tags.length > 0 && (
                  <Card className="p-6">
                    <h3 className="text-lg font-semibold text-theme-primary mb-4">Tags</h3>
                    <div className="flex flex-wrap gap-2">
                      {app.tags.map((tag) => (
                        <Badge key={tag} variant="outline">
                          {tag}
                        </Badge>
                      ))}
                    </div>
                  </Card>
                )}
              </div>

              <div className="space-y-6">
                <Card className="p-6">
                  <h3 className="text-lg font-semibold text-theme-primary mb-4">Quick Stats</h3>
                  <div className="space-y-4">
                    <div className="flex justify-between">
                      <span className="text-theme-secondary">API Endpoints</span>
                      <span className="font-semibold">{endpoints.length}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-theme-secondary">Webhooks</span>
                      <span className="font-semibold">{webhooks.length}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-theme-secondary">Status</span>
                      <Badge variant={getStatusBadgeVariant(app.status)} className="text-xs">
                        {formatStatus(app.status)}
                      </Badge>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-theme-secondary">Version</span>
                      <span className="font-semibold">v{app.version}</span>
                    </div>
                  </div>
                </Card>
              </div>
            </div>
          )}

          {activeTab === 'endpoints' && (
            <div className="space-y-6">
              {endpointsLoading ? (
                <div className="flex justify-center py-12">
                  <LoadingSpinner />
                </div>
              ) : endpoints.length === 0 ? (
                <Card className="p-12 text-center">
                  <div className="text-6xl mb-4">📡</div>
                  <h3 className="text-xl font-semibold text-theme-primary mb-2">No API endpoints yet</h3>
                  <p className="text-theme-secondary mb-6">
                    API endpoints allow other apps to interact with your app's functionality.
                  </p>
                  <Button variant="primary">Create First Endpoint</Button>
                </Card>
              ) : (
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                  {endpoints.map((endpoint) => (
                    <EndpointCard key={endpoint.id} endpoint={endpoint} />
                  ))}
                </div>
              )}
            </div>
          )}

          {activeTab === 'webhooks' && (
            <WebhooksList
              appId={appId!}
              onWebhookAction={handleWebhookAction}
              showCreateButton={true}
            />
          )}

          {activeTab === 'analytics' && (
            <Card className="p-12 text-center">
              <div className="text-6xl mb-4">📈</div>
              <h3 className="text-xl font-semibold text-theme-primary mb-2">Analytics Coming Soon</h3>
              <p className="text-theme-secondary">
                Detailed analytics and usage metrics for your app will be available here.
              </p>
            </Card>
          )}
        </div>
      </div>

    </PageContainer>
  );
};