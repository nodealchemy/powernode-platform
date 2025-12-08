import React, { useState, useEffect, useCallback } from 'react';
import { Button } from '@/shared/components/ui/Button';
import {
  RefreshCw,
  AlertTriangle,
  Clock,
  XCircle,
  Filter,
  Globe,
  ExternalLink,
  ChevronDown,
  ChevronUp,
  AlertCircle,
  CheckCircle,
  Calendar,
} from 'lucide-react';
import { webhooksApi, FailedDelivery, WebhookEndpoint } from '@/features/webhooks/services/webhooksApi';
import Pagination from '@/shared/components/ui/Pagination';

interface WebhookRetryDashboardProps {
  onRetrySuccess?: () => void;
}

interface Summary {
  total_failed: number;
  failed_today: number;
  max_retries_reached: number;
  unique_endpoints_affected: number;
  oldest_failure?: string;
}

interface Filters {
  webhook_id: string;
  status: '' | 'failed' | 'max_retries_reached';
  event_type: string;
  date_from: string;
  date_to: string;
}

export const WebhookRetryDashboard: React.FC<WebhookRetryDashboardProps> = ({
  onRetrySuccess,
}) => {
  const [deliveries, setDeliveries] = useState<FailedDelivery[]>([]);
  const [webhooks, setWebhooks] = useState<WebhookEndpoint[]>([]);
  const [summary, setSummary] = useState<Summary>({
    total_failed: 0,
    failed_today: 0,
    max_retries_reached: 0,
    unique_endpoints_affected: 0,
  });
  const [pagination, setPagination] = useState({
    current_page: 1,
    per_page: 20,
    total_pages: 1,
    total_count: 0,
  });
  const [loading, setLoading] = useState(true);
  const [retrying, setRetrying] = useState<string | null>(null);
  const [bulkRetrying, setBulkRetrying] = useState(false);
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());
  const [showFilters, setShowFilters] = useState(false);
  const [filters, setFilters] = useState<Filters>({
    webhook_id: '',
    status: '',
    event_type: '',
    date_from: '',
    date_to: '',
  });

  // Load webhooks for filter dropdown
  useEffect(() => {
    const loadWebhooks = async () => {
      const response = await webhooksApi.getWebhooks(1, 100);
      if (response.success && response.data?.webhooks) {
        setWebhooks(response.data.webhooks);
      }
    };
    loadWebhooks();
  }, []);

  // Load failed deliveries
  const loadFailedDeliveries = useCallback(async (page = 1) => {
    setLoading(true);
    try {
      const response = await webhooksApi.getFailedDeliveries({
        page,
        per_page: 20,
        webhook_id: filters.webhook_id || undefined,
        status: filters.status || undefined,
        event_type: filters.event_type || undefined,
        date_from: filters.date_from || undefined,
        date_to: filters.date_to || undefined,
      });

      if (response.success && response.data) {
        setDeliveries(response.data.deliveries);
        setPagination(response.data.pagination);
        setSummary(response.data.summary);
      }
    } finally {
      setLoading(false);
    }
  }, [filters]);

  useEffect(() => {
    loadFailedDeliveries(1);
  }, [loadFailedDeliveries]);

  // Handle single retry
  const handleRetry = async (delivery: FailedDelivery) => {
    setRetrying(delivery.id);
    try {
      const response = await webhooksApi.retryDelivery(
        delivery.webhook_endpoint_id,
        delivery.id
      );

      if (response.success) {
        // Reload deliveries
        await loadFailedDeliveries(pagination.current_page);
        onRetrySuccess?.();
      }
    } finally {
      setRetrying(null);
    }
  };

  // Handle bulk retry
  const handleBulkRetry = async () => {
    setBulkRetrying(true);
    try {
      const response = await webhooksApi.retryFailed();
      if (response.success) {
        await loadFailedDeliveries(1);
        onRetrySuccess?.();
      }
    } finally {
      setBulkRetrying(false);
    }
  };

  // Toggle row expansion
  const toggleRowExpansion = (deliveryId: string) => {
    const newExpanded = new Set(expandedRows);
    if (newExpanded.has(deliveryId)) {
      newExpanded.delete(deliveryId);
    } else {
      newExpanded.add(deliveryId);
    }
    setExpandedRows(newExpanded);
  };

  // Clear filters
  const clearFilters = () => {
    setFilters({
      webhook_id: '',
      status: '',
      event_type: '',
      date_from: '',
      date_to: '',
    });
  };

  // Format timestamp
  const formatTime = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleString();
  };

  // Format relative time
  const formatRelativeTime = (dateString: string) => {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  };

  // Get unique event types from deliveries
  const eventTypes = Array.from(new Set(deliveries.map(d => d.event_type)));

  const hasActiveFilters = filters.webhook_id || filters.status || filters.event_type || filters.date_from || filters.date_to;

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-error bg-opacity-10">
              <AlertTriangle className="w-5 h-5 text-theme-error" />
            </div>
            <div>
              <div className="text-2xl font-semibold text-theme-primary">
                {summary.total_failed}
              </div>
              <div className="text-sm text-theme-secondary">Total Failed</div>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-warning bg-opacity-10">
              <Clock className="w-5 h-5 text-theme-warning" />
            </div>
            <div>
              <div className="text-2xl font-semibold text-theme-primary">
                {summary.failed_today}
              </div>
              <div className="text-sm text-theme-secondary">Failed Today</div>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-error bg-opacity-20">
              <XCircle className="w-5 h-5 text-theme-error" />
            </div>
            <div>
              <div className="text-2xl font-semibold text-theme-primary">
                {summary.max_retries_reached}
              </div>
              <div className="text-sm text-theme-secondary">Max Retries</div>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-theme-info bg-opacity-10">
              <Globe className="w-5 h-5 text-theme-info" />
            </div>
            <div>
              <div className="text-2xl font-semibold text-theme-primary">
                {summary.unique_endpoints_affected}
              </div>
              <div className="text-sm text-theme-secondary">Affected Endpoints</div>
            </div>
          </div>
        </div>
      </div>

      {/* Actions Bar */}
      <div className="bg-theme-surface rounded-lg border border-theme p-4">
        <div className="flex flex-col sm:flex-row justify-between gap-4">
          <div className="flex items-center gap-3">
            <Button
              onClick={() => setShowFilters(!showFilters)}
              variant="outline"
              className="flex items-center gap-2"
            >
              <Filter className="w-4 h-4" />
              Filters
              {hasActiveFilters && (
                <span className="ml-1 px-1.5 py-0.5 text-xs bg-theme-primary text-white rounded-full">
                  {[filters.webhook_id, filters.status, filters.event_type, filters.date_from, filters.date_to].filter(Boolean).length}
                </span>
              )}
            </Button>

            {hasActiveFilters && (
              <Button
                onClick={clearFilters}
                variant="outline"
                className="text-sm text-theme-secondary hover:text-theme-primary"
              >
                Clear filters
              </Button>
            )}
          </div>

          <div className="flex items-center gap-3">
            <Button
              onClick={() => loadFailedDeliveries(pagination.current_page)}
              variant="outline"
              disabled={loading}
              className="flex items-center gap-2"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
              Refresh
            </Button>

            <Button
              onClick={handleBulkRetry}
              disabled={bulkRetrying || summary.total_failed === 0}
              className="flex items-center gap-2 bg-theme-primary text-white hover:bg-theme-primary-hover"
            >
              <RefreshCw className={`w-4 h-4 ${bulkRetrying ? 'animate-spin' : ''}`} />
              Retry All Failed
            </Button>
          </div>
        </div>

        {/* Expanded Filters */}
        {showFilters && (
          <div className="mt-4 pt-4 border-t border-theme grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
            {/* Webhook Filter */}
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Webhook
              </label>
              <select
                value={filters.webhook_id}
                onChange={(e) => setFilters({ ...filters, webhook_id: e.target.value })}
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              >
                <option value="">All Webhooks</option>
                {webhooks.map((webhook) => (
                  <option key={webhook.id} value={webhook.id}>
                    {webhook.description || webhooksApi.formatUrl(webhook.url, 30)}
                  </option>
                ))}
              </select>
            </div>

            {/* Status Filter */}
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Status
              </label>
              <select
                value={filters.status}
                onChange={(e) => setFilters({ ...filters, status: e.target.value as '' | 'failed' | 'max_retries_reached' })}
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              >
                <option value="">All Status</option>
                <option value="failed">Failed (Retryable)</option>
                <option value="max_retries_reached">Max Retries Reached</option>
              </select>
            </div>

            {/* Event Type Filter */}
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Event Type
              </label>
              <select
                value={filters.event_type}
                onChange={(e) => setFilters({ ...filters, event_type: e.target.value })}
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              >
                <option value="">All Events</option>
                {eventTypes.map((eventType) => (
                  <option key={eventType} value={eventType}>
                    {webhooksApi.formatEventType(eventType)}
                  </option>
                ))}
              </select>
            </div>

            {/* Date From */}
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                From Date
              </label>
              <input
                type="date"
                value={filters.date_from}
                onChange={(e) => setFilters({ ...filters, date_from: e.target.value })}
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
            </div>

            {/* Date To */}
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                To Date
              </label>
              <input
                type="date"
                value={filters.date_to}
                onChange={(e) => setFilters({ ...filters, date_to: e.target.value })}
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>
        )}
      </div>

      {/* Deliveries Table */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        {loading ? (
          <div className="p-8 text-center">
            <RefreshCw className="w-8 h-8 text-theme-tertiary mx-auto animate-spin mb-4" />
            <p className="text-theme-secondary">Loading failed deliveries...</p>
          </div>
        ) : deliveries.length === 0 ? (
          <div className="p-8 text-center">
            <CheckCircle className="w-12 h-12 text-theme-success mx-auto mb-4" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">No failed deliveries</h3>
            <p className="text-theme-secondary">
              {hasActiveFilters
                ? 'No failed deliveries match your filters'
                : 'All webhook deliveries have been successful'}
            </p>
          </div>
        ) : (
          <>
            {/* Desktop Table */}
            <div className="hidden md:block">
              <table className="w-full">
                <thead>
                  <tr className="bg-theme-background border-b border-theme">
                    <th className="text-left py-3 px-4 font-medium text-theme-primary">
                      Webhook
                    </th>
                    <th className="text-left py-3 px-4 font-medium text-theme-primary">
                      Event
                    </th>
                    <th className="text-left py-3 px-4 font-medium text-theme-primary">
                      Status
                    </th>
                    <th className="text-left py-3 px-4 font-medium text-theme-primary">
                      Attempts
                    </th>
                    <th className="text-left py-3 px-4 font-medium text-theme-primary">
                      Failed At
                    </th>
                    <th className="text-right py-3 px-4 font-medium text-theme-primary">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-theme">
                  {deliveries.map((delivery) => {
                    const isExpanded = expandedRows.has(delivery.id);
                    const canRetry = delivery.status !== 'max_retries_reached';

                    return (
                      <React.Fragment key={delivery.id}>
                        <tr className="hover:bg-theme-surface-hover transition-colors duration-200">
                          <td className="py-3 px-4">
                            <div>
                              <div className="flex items-center gap-2">
                                <Globe className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                                <span className="font-medium text-theme-primary truncate" title={delivery.webhook_endpoint?.url}>
                                  {webhooksApi.formatUrl(delivery.webhook_endpoint?.url || '', 30)}
                                </span>
                                <ExternalLink className="w-3 h-3 text-theme-tertiary" />
                              </div>
                              {delivery.webhook_endpoint?.description && (
                                <p className="text-sm text-theme-secondary mt-1 truncate">
                                  {delivery.webhook_endpoint.description}
                                </p>
                              )}
                            </div>
                          </td>

                          <td className="py-3 px-4">
                            <span className="text-sm text-theme-primary">
                              {webhooksApi.formatEventType(delivery.event_type)}
                            </span>
                          </td>

                          <td className="py-3 px-4">
                            <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
                              webhooksApi.getDeliveryStatusColor(delivery.status)
                            }`}>
                              {delivery.status === 'max_retries_reached' ? (
                                <XCircle className="w-3 h-3 mr-1" />
                              ) : (
                                <AlertCircle className="w-3 h-3 mr-1" />
                              )}
                              {delivery.status === 'max_retries_reached' ? 'Max Retries' : 'Failed'}
                            </span>
                          </td>

                          <td className="py-3 px-4">
                            <div className="flex items-center gap-2">
                              <span className="text-sm font-medium text-theme-primary">
                                {delivery.attempt_count}
                              </span>
                              <span className="text-sm text-theme-secondary">attempts</span>
                            </div>
                            {delivery.http_status && (
                              <div className="text-xs text-theme-tertiary">
                                HTTP {delivery.http_status}
                              </div>
                            )}
                          </td>

                          <td className="py-3 px-4">
                            <div>
                              <div className="text-sm text-theme-primary">
                                {formatRelativeTime(delivery.created_at)}
                              </div>
                              <div className="text-xs text-theme-tertiary">
                                {formatTime(delivery.created_at)}
                              </div>
                            </div>
                          </td>

                          <td className="py-3 px-4">
                            <div className="flex items-center justify-end gap-2">
                              <Button
                                onClick={() => toggleRowExpansion(delivery.id)}
                                variant="outline"
                                className="p-1 text-theme-secondary hover:text-theme-primary transition-colors duration-200"
                                title="View Details"
                              >
                                {isExpanded ? (
                                  <ChevronUp className="w-4 h-4" />
                                ) : (
                                  <ChevronDown className="w-4 h-4" />
                                )}
                              </Button>

                              <Button
                                onClick={() => handleRetry(delivery)}
                                disabled={!canRetry || retrying === delivery.id}
                                variant="outline"
                                className={`p-1 transition-colors duration-200 ${
                                  canRetry
                                    ? 'text-theme-primary hover:text-theme-primary-hover'
                                    : 'text-theme-tertiary cursor-not-allowed'
                                }`}
                                title={canRetry ? 'Retry Delivery' : 'Max retries reached'}
                              >
                                <RefreshCw className={`w-4 h-4 ${retrying === delivery.id ? 'animate-spin' : ''}`} />
                              </Button>
                            </div>
                          </td>
                        </tr>

                        {/* Expanded Row - Error Details */}
                        {isExpanded && (
                          <tr>
                            <td colSpan={6} className="px-4 py-3 bg-theme-background border-b border-theme">
                              <div className="space-y-3">
                                {delivery.error_message && (
                                  <div>
                                    <h4 className="text-sm font-medium text-theme-primary mb-1">
                                      Error Message
                                    </h4>
                                    <pre className="text-xs text-theme-error bg-theme-error bg-opacity-5 p-2 rounded overflow-x-auto">
                                      {delivery.error_message}
                                    </pre>
                                  </div>
                                )}

                                {delivery.last_response_body && (
                                  <div>
                                    <h4 className="text-sm font-medium text-theme-primary mb-1">
                                      Last Response
                                    </h4>
                                    <pre className="text-xs text-theme-secondary bg-theme-surface p-2 rounded overflow-x-auto max-h-32">
                                      {delivery.last_response_body}
                                    </pre>
                                  </div>
                                )}

                                {delivery.next_retry_at && (
                                  <div className="flex items-center gap-2 text-sm text-theme-secondary">
                                    <Clock className="w-4 h-4" />
                                    <span>Next retry scheduled: {formatTime(delivery.next_retry_at)}</span>
                                  </div>
                                )}

                                {delivery.response_time_ms && (
                                  <div className="text-sm text-theme-secondary">
                                    Response time: {delivery.response_time_ms}ms
                                  </div>
                                )}
                              </div>
                            </td>
                          </tr>
                        )}
                      </React.Fragment>
                    );
                  })}
                </tbody>
              </table>
            </div>

            {/* Mobile Cards */}
            <div className="md:hidden divide-y divide-theme">
              {deliveries.map((delivery) => {
                const isExpanded = expandedRows.has(delivery.id);
                const canRetry = delivery.status !== 'max_retries_reached';

                return (
                  <div key={delivery.id} className="p-4">
                    {/* Header */}
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1">
                          <Globe className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                          <span className="font-medium text-theme-primary truncate">
                            {webhooksApi.formatUrl(delivery.webhook_endpoint?.url || '', 25)}
                          </span>
                        </div>
                        <div className="text-sm text-theme-secondary">
                          {webhooksApi.formatEventType(delivery.event_type)}
                        </div>
                      </div>

                      <div className="flex items-center gap-2">
                        <Button
                          onClick={() => toggleRowExpansion(delivery.id)}
                          variant="outline"
                          className="p-1 text-theme-secondary"
                        >
                          {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                        </Button>
                        <Button
                          onClick={() => handleRetry(delivery)}
                          disabled={!canRetry || retrying === delivery.id}
                          variant="outline"
                          className="p-1"
                        >
                          <RefreshCw className={`w-4 h-4 ${retrying === delivery.id ? 'animate-spin' : ''}`} />
                        </Button>
                      </div>
                    </div>

                    {/* Stats */}
                    <div className="grid grid-cols-3 gap-4 mb-3">
                      <div className="text-center">
                        <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
                          webhooksApi.getDeliveryStatusColor(delivery.status)
                        }`}>
                          {delivery.status === 'max_retries_reached' ? 'Max Retries' : 'Failed'}
                        </span>
                      </div>

                      <div className="text-center">
                        <div className="text-sm font-medium text-theme-primary">
                          {delivery.attempt_count}
                        </div>
                        <div className="text-xs text-theme-secondary">Attempts</div>
                      </div>

                      <div className="text-center">
                        <div className="text-sm font-medium text-theme-primary">
                          {delivery.http_status || 'N/A'}
                        </div>
                        <div className="text-xs text-theme-secondary">HTTP</div>
                      </div>
                    </div>

                    {/* Timestamp */}
                    <div className="text-xs text-theme-tertiary">
                      Failed: {formatRelativeTime(delivery.created_at)}
                    </div>

                    {/* Expanded Details */}
                    {isExpanded && (
                      <div className="mt-3 pt-3 border-t border-theme space-y-2">
                        {delivery.error_message && (
                          <div>
                            <div className="text-xs font-medium text-theme-secondary mb-1">Error:</div>
                            <pre className="text-xs text-theme-error bg-theme-error bg-opacity-5 p-2 rounded overflow-x-auto">
                              {delivery.error_message}
                            </pre>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </>
        )}
      </div>

      {/* Pagination */}
      {pagination.total_pages > 1 && (
        <div className="flex justify-center">
          <Pagination
            currentPage={pagination.current_page}
            totalPages={pagination.total_pages}
            onPageChange={(page) => loadFailedDeliveries(page)}
          />
        </div>
      )}

      {/* Oldest Failure Info */}
      {summary.oldest_failure && (
        <div className="text-center text-sm text-theme-secondary">
          <Calendar className="w-4 h-4 inline-block mr-2" />
          Oldest failure: {formatTime(summary.oldest_failure)}
        </div>
      )}
    </div>
  );
};

export default WebhookRetryDashboard;
