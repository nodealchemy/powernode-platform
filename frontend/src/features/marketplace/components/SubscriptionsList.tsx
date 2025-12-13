import { useState, forwardRef, useImperativeHandle } from 'react';
import { Search, Filter, RefreshCw } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { SubscriptionCard } from './SubscriptionCard';
import { useAppSubscriptions } from '../hooks/useAppSubscriptions';

interface SubscriptionsListProps {
  className?: string;
  onSubscriptionAction?: (action: string, subscriptionId: string) => void;
  showRefreshButton?: boolean;
}

interface SubscriptionsListRef {
  refresh: () => void;
}

const statusOptions = [
  { value: 'all', label: 'All Subscriptions', count: 0 },
  { value: 'active', label: 'Active', count: 0 },
  { value: 'paused', label: 'Paused', count: 0 },
  { value: 'cancelled', label: 'Cancelled', count: 0 },
  { value: 'expired', label: 'Expired', count: 0 }
];

export const SubscriptionsList = forwardRef<SubscriptionsListRef, SubscriptionsListProps>(({
  className = '',
  onSubscriptionAction,
  showRefreshButton = true
}, ref) => {
  const [selectedStatus, setSelectedStatus] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');

  const {
    subscriptions,
    loading,
    error,
    pagination,
    refreshSubscriptions,
    loadMore,
    pauseSubscription,
    resumeSubscription,
    cancelSubscription,
    upgradePlan,
    downgradePlan
  } = useAppSubscriptions(selectedStatus === 'all' ? undefined : selectedStatus);
  
  // Expose refresh function to parent component via ref
  useImperativeHandle(ref, () => ({
    refresh: refreshSubscriptions
  }), [refreshSubscriptions]);

  // Filter subscriptions by search query
  const filteredSubscriptions = subscriptions.filter(subscription =>
    subscription.app.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    subscription.app_plan.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  // Update status counts
  const statusCounts = statusOptions.map(option => ({
    ...option,
    count: option.value === 'all' 
      ? subscriptions.length
      : subscriptions.filter(sub => sub.status === option.value).length
  }));

  const handlePause = async (id: string, reason?: string) => {
    await pauseSubscription(id, reason);
    onSubscriptionAction?.('pause', id);
  };

  const handleResume = async (id: string) => {
    await resumeSubscription(id);
    onSubscriptionAction?.('resume', id);
  };

  const handleCancel = async (id: string, reason?: string) => {
    if (window.confirm('Are you sure you want to cancel this subscription?')) {
      await cancelSubscription(id, reason);
      onSubscriptionAction?.('cancel', id);
    }
  };

  const handleUpgrade = async (id: string, newPlanId: string) => {
    await upgradePlan(id, newPlanId);
    onSubscriptionAction?.('upgrade', id);
  };

  const handleDowngrade = async (id: string, newPlanId: string) => {
    await downgradePlan(id, newPlanId);
    onSubscriptionAction?.('downgrade', id);
  };

  const handleViewUsage = (id: string) => {
    onSubscriptionAction?.('view-usage', id);
  };

  const handleViewAnalytics = (id: string) => {
    onSubscriptionAction?.('view-analytics', id);
  };

  const handleConfigure = (id: string) => {
    onSubscriptionAction?.('configure', id);
  };

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Header */}
      <div className={`flex flex-col ${showRefreshButton ? 'sm:flex-row sm:items-center sm:justify-between' : ''} gap-4`}>
        <div>
          <h2 className="text-2xl font-bold text-theme-primary">Your Subscriptions</h2>
          <p className="text-theme-secondary">Manage your app subscriptions and usage</p>
        </div>
        
        {showRefreshButton && (
          <Button
            variant="outline"
            onClick={refreshSubscriptions}
            disabled={loading}
            className="flex items-center space-x-2"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            <span>Refresh</span>
          </Button>
        )}
      </div>

      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        {/* Search */}
        <div className="relative flex-1">
          <Search className="w-5 h-5 absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary" />
          <input
            type="text"
            placeholder="Search subscriptions..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
          />
        </div>

        {/* Status Filter */}
        <div className="flex items-center space-x-2">
          <Filter className="w-4 h-4 text-theme-tertiary" />
          <div className="flex flex-wrap gap-2">
            {statusCounts.map((status) => (
              <button
                key={status.value}
                onClick={() => setSelectedStatus(status.value)}
                className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                  selectedStatus === status.value
                    ? 'bg-theme-interactive-primary text-white'
                    : 'bg-theme-surface text-theme-secondary hover:bg-theme-interactive-primary/10'
                }`}
              >
                {status.label}
                {status.count > 0 && (
                  <Badge variant="secondary" className="ml-1">
                    {status.count}
                  </Badge>
                )}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Loading State */}
      {loading && subscriptions.length === 0 && (
        <div className="flex justify-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      )}

      {/* Error State */}
      {error && (
        <div className="bg-theme-error-background border border-theme-error-border rounded-lg p-6 text-center">
          <p className="text-theme-error mb-4">{error}</p>
          <Button variant="outline" onClick={refreshSubscriptions}>
            Try Again
          </Button>
        </div>
      )}

      {/* Empty State */}
      {!loading && !error && filteredSubscriptions.length === 0 && (
        <div className="text-center py-12">
          <div className="w-16 h-16 bg-theme-interactive-primary/10 rounded-full flex items-center justify-center mx-auto mb-4">
            <span className="text-2xl">📱</span>
          </div>
          <h3 className="text-lg font-semibold text-theme-primary mb-2">
            {subscriptions.length === 0 ? 'No subscriptions yet' : 'No matching subscriptions'}
          </h3>
          <p className="text-theme-secondary">
            {subscriptions.length === 0 
              ? 'Browse the marketplace to subscribe to apps'
              : 'Try adjusting your search or filter criteria'
            }
          </p>
        </div>
      )}

      {/* Subscriptions Grid */}
      {!loading && !error && filteredSubscriptions.length > 0 && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {filteredSubscriptions.map((subscription) => (
            <SubscriptionCard
              key={subscription.id}
              subscription={subscription}
              onPause={handlePause}
              onResume={handleResume}
              onCancel={handleCancel}
              onUpgrade={handleUpgrade}
              onDowngrade={handleDowngrade}
              onViewUsage={handleViewUsage}
              onViewAnalytics={handleViewAnalytics}
              onConfigure={handleConfigure}
              isLoading={loading}
            />
          ))}
        </div>
      )}

      {/* Load More */}
      {pagination && pagination.current_page < pagination.total_pages && (
        <div className="text-center py-6">
          <Button
            variant="outline"
            onClick={loadMore}
            disabled={loading}
            className="flex items-center space-x-2"
          >
            <span>Load More</span>
            {loading && <LoadingSpinner size="sm" />}
          </Button>
        </div>
      )}

      {/* Stats Footer */}
      {pagination && (
        <div className="text-center text-sm text-theme-secondary">
          Showing {filteredSubscriptions.length} of {pagination.total_count} subscriptions
        </div>
      )}
    </div>
  );
});

// Add display name for debugging
