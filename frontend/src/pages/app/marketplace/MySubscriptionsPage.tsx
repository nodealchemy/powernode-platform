/**
 * My Subscriptions Page
 *
 * Lists all marketplace subscriptions for the current account across all template types
 * (workflows, pipelines, integrations, prompts).
 */

import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Package, Settings, Pause, Play, Trash2, AlertCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { marketplaceApi } from '@/features/app/services/marketplaceApi';
import type { MarketplaceSubscription, MarketplaceItemType } from '@/features/app/types/marketplace';
import { ALL_MARKETPLACE_TYPES } from '@/features/app/types/marketplace';

const ALL_TYPES = ALL_MARKETPLACE_TYPES;

export const MySubscriptionsPage: React.FC = () => {
  const navigate = useNavigate();
  const { addNotification } = useNotifications();
  usePageWebSocket({ pageType: 'marketplace' });

  const [subscriptions, setSubscriptions] = useState<MarketplaceSubscription[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [selectedType, setSelectedType] = useState<MarketplaceItemType | 'all'>('all');
  const [selectedStatus, setSelectedStatus] = useState<string>('all');

  // Load subscriptions
  const loadSubscriptions = useCallback(async () => {
    try {
      setLoading(true);
      const params: { type?: MarketplaceItemType; status?: string } = {};

      if (selectedType !== 'all') {
        params.type = selectedType;
      }
      if (selectedStatus !== 'all') {
        params.status = selectedStatus;
      }

      const response = await marketplaceApi.getSubscriptions(params);
      setSubscriptions(response.data || []);
    } catch {
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load subscriptions. Please try again.'
      });
    } finally {
      setLoading(false);
    }
  }, [selectedType, selectedStatus, addNotification]);

  useEffect(() => {
    loadSubscriptions();
  }, [loadSubscriptions]);

  const handlePause = async (subscriptionId: string) => {
    try {
      setActionLoading(subscriptionId);
      await marketplaceApi.pauseSubscription(subscriptionId);
      addNotification({
        type: 'success',
        title: 'Subscription Paused',
        message: 'Your subscription has been paused.'
      });
      loadSubscriptions();
    } catch {
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to pause subscription. Please try again.'
      });
    } finally {
      setActionLoading(null);
    }
  };

  const handleResume = async (subscriptionId: string) => {
    try {
      setActionLoading(subscriptionId);
      await marketplaceApi.resumeSubscription(subscriptionId);
      addNotification({
        type: 'success',
        title: 'Subscription Resumed',
        message: 'Your subscription has been resumed.'
      });
      loadSubscriptions();
    } catch {
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to resume subscription. Please try again.'
      });
    } finally {
      setActionLoading(null);
    }
  };

  const handleCancel = async (subscriptionId: string) => {
    if (!confirm('Are you sure you want to cancel this subscription?')) {
      return;
    }

    try {
      setActionLoading(subscriptionId);
      await marketplaceApi.cancelSubscription(subscriptionId);
      addNotification({
        type: 'success',
        title: 'Subscription Cancelled',
        message: 'Your subscription has been cancelled.'
      });
      loadSubscriptions();
    } catch {
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to cancel subscription. Please try again.'
      });
    } finally {
      setActionLoading(null);
    }
  };

  const handleViewDetails = (subscription: MarketplaceSubscription) => {
    navigate(`/app/marketplace/${subscription.item_type}/${subscription.item_id}`);
  };

  const getTypeBadgeColor = (type: string) => {
    switch (type) {
      case 'app':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'plugin':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'template':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'integration':
        return 'bg-theme-primary bg-opacity-10 text-theme-primary';
      default:
        return 'bg-theme-surface text-theme-primary';
    }
  };

  const getStatusBadgeColor = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'paused':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'cancelled':
      case 'expired':
        return 'bg-theme-danger bg-opacity-10 text-theme-danger';
      default:
        return 'bg-theme-surface text-theme-primary';
    }
  };

  const getButtonClass = (isActive: boolean) => {
    return `px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
      isActive
        ? 'bg-theme-interactive-primary text-theme-on-primary'
        : 'bg-theme-surface text-theme-tertiary hover:bg-theme-surface-hover border border-theme'
    }`;
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Marketplace', href: '/app/marketplace' },
    { label: 'My Subscriptions' }
  ];

  if (loading) {
    return (
      <PageContainer
        title="My Subscriptions"
        description="Manage your marketplace subscriptions"
        breadcrumbs={breadcrumbs}
      >
        <LoadingSpinner className="py-12" />
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="My Subscriptions"
      description="Manage your marketplace subscriptions"
      breadcrumbs={breadcrumbs}
      actions={[
        {
          label: 'Browse Marketplace',
          onClick: () => navigate('/app/marketplace'),
          variant: 'primary' as const
        }
      ]}
    >
      {/* Filters */}
      <div className="mb-6 flex flex-wrap items-center gap-4">
        {/* Type filter */}
        <div className="flex items-center gap-2">
          <span className="text-sm text-theme-tertiary">Type:</span>
          <button
            onClick={() => setSelectedType('all')}
            className={getButtonClass(selectedType === 'all')}
          >
            All
          </button>
          {ALL_TYPES.map((type) => (
            <button
              key={type}
              onClick={() => setSelectedType(type)}
              className={getButtonClass(selectedType === type)}
            >
              {type.charAt(0).toUpperCase() + type.slice(1)}s
            </button>
          ))}
        </div>

        {/* Status filter */}
        <div className="flex items-center gap-2">
          <span className="text-sm text-theme-tertiary">Status:</span>
          <button
            onClick={() => setSelectedStatus('all')}
            className={getButtonClass(selectedStatus === 'all')}
          >
            All
          </button>
          <button
            onClick={() => setSelectedStatus('active')}
            className={getButtonClass(selectedStatus === 'active')}
          >
            Active
          </button>
          <button
            onClick={() => setSelectedStatus('paused')}
            className={getButtonClass(selectedStatus === 'paused')}
          >
            Paused
          </button>
        </div>
      </div>

      {/* Subscriptions List */}
      {subscriptions.length === 0 ? (
        <EmptyState
          icon={Package}
          title="No subscriptions yet"
          description="Browse the marketplace to find apps, plugins, templates, and integrations"
          action={
            <Button onClick={() => navigate('/app/marketplace')}>
              Browse Marketplace
            </Button>
          }
        />
      ) : (
        <div className="space-y-4">
          {subscriptions.map((subscription) => (
            <Card key={subscription.id} className="p-4">
              <div className="flex items-start justify-between gap-4">
                {/* Item info */}
                <div className="flex items-start gap-4 flex-1 min-w-0">
                  <div className="h-12 w-12 bg-theme-surface rounded-lg flex items-center justify-center border border-theme flex-shrink-0">
                    {subscription.item_icon ? (
                      <img
                        src={subscription.item_icon}
                        alt={subscription.item_name}
                        className="h-8 w-8 object-contain"
                      />
                    ) : (
                      <Package className="h-6 w-6 text-theme-tertiary" />
                    )}
                  </div>

                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <h3 className="text-lg font-semibold text-theme-primary truncate">
                        {subscription.item_name}
                      </h3>
                      <span
                        className={`px-2 py-0.5 rounded text-xs font-medium ${getTypeBadgeColor(subscription.item_type)}`}
                      >
                        {subscription.item_type.charAt(0).toUpperCase() + subscription.item_type.slice(1)}
                      </span>
                      <span
                        className={`px-2 py-0.5 rounded text-xs font-medium ${getStatusBadgeColor(subscription.status)}`}
                      >
                        {subscription.status.charAt(0).toUpperCase() + subscription.status.slice(1)}
                      </span>
                    </div>

                    <div className="flex items-center gap-4 mt-1 text-sm text-theme-tertiary">
                      {subscription.tier && (
                        <span>Tier: {subscription.tier}</span>
                      )}
                      <span>
                        Subscribed: {new Date(subscription.subscribed_at).toLocaleDateString()}
                      </span>
                    </div>

                    {subscription.status === 'paused' && (
                      <div className="flex items-center gap-1 mt-2 text-sm text-theme-warning">
                        <AlertCircle className="h-4 w-4" />
                        <span>This subscription is paused</span>
                      </div>
                    )}
                  </div>
                </div>

                {/* Actions */}
                <div className="flex items-center gap-2 flex-shrink-0">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleViewDetails(subscription)}
                    className="text-xs"
                  >
                    View
                  </Button>

                  {subscription.status === 'active' && (
                    <>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => navigate(`/app/marketplace/subscriptions/${subscription.id}/configure`)}
                        className="text-xs"
                        title="Configure"
                      >
                        <Settings className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => handlePause(subscription.id)}
                        disabled={actionLoading === subscription.id}
                        className="text-xs"
                        title="Pause"
                      >
                        <Pause className="h-4 w-4" />
                      </Button>
                    </>
                  )}

                  {subscription.status === 'paused' && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleResume(subscription.id)}
                      disabled={actionLoading === subscription.id}
                      className="text-xs"
                      title="Resume"
                    >
                      <Play className="h-4 w-4" />
                    </Button>
                  )}

                  {['active', 'paused'].includes(subscription.status) && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleCancel(subscription.id)}
                      disabled={actionLoading === subscription.id}
                      className="text-xs text-theme-danger hover:text-theme-danger"
                      title="Cancel"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  )}
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}
    </PageContainer>
  );
};
