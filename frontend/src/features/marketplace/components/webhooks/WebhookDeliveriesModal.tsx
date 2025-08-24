import React, { useState, useEffect, useCallback } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useAppWebhook } from '../../hooks/useWebhooks';
import { AppWebhook, AppWebhookDelivery, DeliveryStatus } from '../../types';
import { X, RefreshCw, Search, Filter, Eye, Clock, AlertTriangle, CheckCircle, RotateCcw } from 'lucide-react';

interface WebhookDeliveriesModalProps {
  isOpen: boolean;
  onClose: () => void;
  appId: string;
  webhook: AppWebhook;
}

interface DeliveryFilters {
  status?: DeliveryStatus;
  event_id?: string;
  days?: number;
  page?: number;
  per_page?: number;
}

export const WebhookDeliveriesModal: React.FC<WebhookDeliveriesModalProps> = ({
  isOpen,
  onClose,
  appId,
  webhook
}) => {
  const [deliveries, setDeliveries] = useState<AppWebhookDelivery[]>([]);
  const [loading, setLoading] = useState(true);
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 20
  });
  const [filters, setFilters] = useState<DeliveryFilters>({
    days: 7,
    page: 1,
    per_page: 20
  });
  const [expandedDelivery, setExpandedDelivery] = useState<string | null>(null);

  const { getDeliveries } = useAppWebhook(appId, webhook.id);

  const loadDeliveries = useCallback(async () => {
    setLoading(true);
    try {
      const response = await getDeliveries(filters);
      if (response) {
        setDeliveries(response.data);
        setPagination(response.pagination);
      }
    } catch (error) {
      console.error('Failed to load deliveries:', error);
    } finally {
      setLoading(false);
    }
  }, [getDeliveries, filters]);

  useEffect(() => {
    if (isOpen) {
      loadDeliveries();
    }
  }, [isOpen, filters, loadDeliveries]);

  const handleFilterChange = (key: keyof DeliveryFilters, value: any) => {
    setFilters({ ...filters, [key]: value, page: 1 }); // Reset to first page
  };

  const handlePageChange = (page: number) => {
    setFilters({ ...filters, page });
  };

  const getStatusBadgeVariant = (status: DeliveryStatus): 'success' | 'warning' | 'danger' | 'secondary' => {
    switch (status) {
      case 'delivered': return 'success';
      case 'pending': return 'warning';
      case 'failed': return 'danger';
      case 'cancelled': return 'secondary';
      default: return 'secondary';
    }
  };

  const getStatusIcon = (status: DeliveryStatus) => {
    switch (status) {
      case 'delivered':
        return <CheckCircle className="w-4 h-4 text-theme-success" />;
      case 'pending':
        return <Clock className="w-4 h-4 text-theme-warning" />;
      case 'failed':
        return <AlertTriangle className="w-4 h-4 text-theme-error" />;
      case 'cancelled':
        return <X className="w-4 h-4 text-theme-secondary" />;
      default:
        return null;
    }
  };

  const formatResponseTime = (ms?: number) => {
    if (!ms) return 'N/A';
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (days > 0) return `${days}d ago`;
    if (hours > 0) return `${hours}h ago`;
    if (minutes > 0) return `${minutes}m ago`;
    return 'Just now';
  };

  const toggleDeliveryExpansion = (deliveryId: string) => {
    setExpandedDelivery(expandedDelivery === deliveryId ? null : deliveryId);
  };

  return (
    <Modal 
      isOpen={isOpen} 
      onClose={onClose} 
      title="Webhook Deliveries"
      subtitle={webhook.name}
      maxWidth="4xl"
      showCloseButton={false}
    >
      <div className="flex flex-col h-full max-h-[calc(90vh-120px)]">
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <Button variant="outline" size="sm" onClick={loadDeliveries}>
            <RefreshCw className="w-4 h-4" />
          </Button>
          <Button variant="outline" size="sm" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </div>

        <div className="p-6">
          {/* Filters */}
          <div className="mb-6 space-y-4">
            <div className="flex flex-col md:flex-row md:items-end md:space-x-4 space-y-4 md:space-y-0">
              <div className="flex-1">
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Event ID
                </label>
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
                  <input
                    type="text"
                    value={filters.event_id || ''}
                    onChange={(e) => handleFilterChange('event_id', e.target.value)}
                    placeholder="Search by event ID..."
                    className="input-theme pl-10 w-full"
                  />
                </div>
              </div>

              <div className="w-full md:w-40">
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Status
                </label>
                <select
                  value={filters.status || ''}
                  onChange={(e) => handleFilterChange('status', e.target.value || undefined)}
                  className="input-theme w-full"
                >
                  <option value="">All Status</option>
                  <option value="delivered">Delivered</option>
                  <option value="pending">Pending</option>
                  <option value="failed">Failed</option>
                  <option value="cancelled">Cancelled</option>
                </select>
              </div>

              <div className="w-full md:w-32">
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Time Range
                </label>
                <select
                  value={filters.days || 7}
                  onChange={(e) => handleFilterChange('days', parseInt(e.target.value))}
                  className="input-theme w-full"
                >
                  <option value={1}>Last 24h</option>
                  <option value={7}>Last 7 days</option>
                  <option value={30}>Last 30 days</option>
                  <option value={90}>Last 90 days</option>
                </select>
              </div>

              <Button
                variant="outline"
                onClick={() => setFilters({ days: 7, page: 1, per_page: 20 })}
                title="Clear filters"
              >
                <Filter className="w-4 h-4" />
              </Button>
            </div>

            {/* Summary Stats */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div className="bg-theme-background rounded p-3 text-center">
                <div className="font-semibold text-theme-primary">
                  {pagination.total_count}
                </div>
                <div className="text-theme-secondary">Total</div>
              </div>
              <div className="bg-theme-success bg-opacity-10 rounded p-3 text-center">
                <div className="font-semibold text-theme-success">
                  {deliveries.filter(d => d.status === 'delivered').length}
                </div>
                <div className="text-theme-success">Delivered</div>
              </div>
              <div className="bg-theme-warning bg-opacity-10 rounded p-3 text-center">
                <div className="font-semibold text-theme-warning">
                  {deliveries.filter(d => d.status === 'pending').length}
                </div>
                <div className="text-theme-warning">Pending</div>
              </div>
              <div className="bg-theme-error bg-opacity-10 rounded p-3 text-center">
                <div className="font-semibold text-theme-error">
                  {deliveries.filter(d => d.status === 'failed').length}
                </div>
                <div className="text-theme-error">Failed</div>
              </div>
            </div>
          </div>

          {/* Deliveries List */}
          <div className="max-h-[calc(90vh-400px)] overflow-y-auto space-y-4">
            {loading ? (
              <div className="flex justify-center py-12">
                <LoadingSpinner />
              </div>
            ) : deliveries.length === 0 ? (
              <div className="text-center py-12">
                <div className="text-6xl mb-4">📭</div>
                <h3 className="text-xl font-semibold text-theme-primary mb-2">No deliveries found</h3>
                <p className="text-theme-secondary mb-4">
                  {filters.status || filters.event_id || filters.days !== 7
                    ? 'No deliveries match your current filters.'
                    : 'No webhook deliveries have been attempted yet.'
                  }
                </p>
                {filters.status || filters.event_id || filters.days !== 7 ? (
                  <Button variant="outline" onClick={() => setFilters({ days: 7, page: 1, per_page: 20 })}>
                    Clear Filters
                  </Button>
                ) : null}
              </div>
            ) : (
              deliveries.map((delivery) => (
                <div key={delivery.id} className="bg-theme-background rounded-lg p-4 space-y-3">
                  <div className="flex items-start justify-between">
                    <div className="flex items-start space-x-3">
                      {getStatusIcon(delivery.status)}
                      <div className="flex-1">
                        <div className="flex items-center space-x-2 mb-1">
                          <Badge variant={getStatusBadgeVariant(delivery.status)}>
                            {delivery.status.toUpperCase()}
                          </Badge>
                          {delivery.status_code && (
                            <Badge variant="outline">
                              HTTP {delivery.status_code}
                            </Badge>
                          )}
                          <Badge variant="outline" className="font-mono text-xs">
                            Attempt {delivery.attempt_number}
                          </Badge>
                        </div>
                        
                        <div className="text-sm text-theme-secondary">
                          <div className="font-mono">
                            Event: {delivery.event_id}
                          </div>
                          <div className="font-mono">
                            Delivery: {delivery.delivery_id}
                          </div>
                        </div>
                      </div>
                    </div>

                    <div className="text-right text-sm">
                      <div className="text-theme-primary">
                        {delivery.delivered_at
                          ? formatTimestamp(delivery.delivered_at)
                          : formatTimestamp(delivery.created_at)
                        }
                      </div>
                      <div className="text-theme-secondary">
                        {formatResponseTime(delivery.response_time_ms)}
                      </div>
                    </div>
                  </div>

                  {/* Expandable Details */}
                  <div className="flex items-center justify-between pt-2 border-t border-theme">
                    <div className="flex items-center space-x-4 text-sm text-theme-secondary">
                      {delivery.next_retry_at && (
                        <div className="flex items-center space-x-1">
                          <RotateCcw className="w-3 h-3" />
                          <span>Next retry: {formatTimestamp(delivery.next_retry_at)}</span>
                        </div>
                      )}
                      {delivery.error_message && (
                        <div className="text-theme-error">
                          Error: {delivery.error_message.substring(0, 50)}...
                        </div>
                      )}
                    </div>

                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => toggleDeliveryExpansion(delivery.id)}
                    >
                      <Eye className="w-4 h-4 mr-1" />
                      {expandedDelivery === delivery.id ? 'Hide' : 'Details'}
                    </Button>
                  </div>

                  {/* Expanded Details */}
                  {expandedDelivery === delivery.id && (
                    <div className="pt-4 border-t border-theme space-y-4">
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                        <div>
                          <h4 className="font-medium text-theme-primary mb-2">Delivery Info</h4>
                          <div className="space-y-1">
                            <div className="flex justify-between">
                              <span className="text-theme-tertiary">Created:</span>
                              <span className="text-theme-secondary">
                                {new Date(delivery.created_at).toLocaleString()}
                              </span>
                            </div>
                            {delivery.delivered_at && (
                              <div className="flex justify-between">
                                <span className="text-theme-tertiary">Delivered:</span>
                                <span className="text-theme-secondary">
                                  {new Date(delivery.delivered_at).toLocaleString()}
                                </span>
                              </div>
                            )}
                            <div className="flex justify-between">
                              <span className="text-theme-tertiary">Attempt:</span>
                              <span className="text-theme-secondary">
                                {delivery.attempt_number}
                              </span>
                            </div>
                            {delivery.response_time_ms && (
                              <div className="flex justify-between">
                                <span className="text-theme-tertiary">Response Time:</span>
                                <span className="text-theme-secondary">
                                  {formatResponseTime(delivery.response_time_ms)}
                                </span>
                              </div>
                            )}
                          </div>
                        </div>

                        <div>
                          <h4 className="font-medium text-theme-primary mb-2">Status</h4>
                          <div className="space-y-1">
                            <div className="flex justify-between">
                              <span className="text-theme-tertiary">Status:</span>
                              <Badge variant={getStatusBadgeVariant(delivery.status)}>
                                {delivery.status}
                              </Badge>
                            </div>
                            {delivery.status_code && (
                              <div className="flex justify-between">
                                <span className="text-theme-tertiary">HTTP Code:</span>
                                <span className="text-theme-secondary">
                                  {delivery.status_code}
                                </span>
                              </div>
                            )}
                            {delivery.next_retry_at && (
                              <div className="flex justify-between">
                                <span className="text-theme-tertiary">Next Retry:</span>
                                <span className="text-theme-secondary">
                                  {new Date(delivery.next_retry_at).toLocaleString()}
                                </span>
                              </div>
                            )}
                          </div>
                        </div>
                      </div>

                      {delivery.error_message && (
                        <div>
                          <h4 className="font-medium text-theme-primary mb-2">Error Details</h4>
                          <div className="bg-theme-error bg-opacity-10 border border-theme-error border-opacity-20 rounded p-3">
                            <p className="text-theme-error text-sm font-mono">
                              {delivery.error_message}
                            </p>
                          </div>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              ))
            )}
          </div>

          {/* Pagination */}
          {pagination && pagination.total_pages > 1 && (
            <div className="flex justify-center items-center space-x-4 mt-6 pt-6 border-t border-theme">
              <Button
                variant="outline"
                size="sm"
                disabled={pagination.current_page === 1}
                onClick={() => handlePageChange(pagination.current_page - 1)}
              >
                Previous
              </Button>
              
              <div className="flex items-center space-x-2">
                {Array.from({ length: Math.min(5, pagination.total_pages) }, (_, i) => {
                  const pageNum = i + 1;
                  return (
                    <Button
                      key={pageNum}
                      variant={pagination.current_page === pageNum ? 'primary' : 'outline'}
                      size="sm"
                      onClick={() => handlePageChange(pageNum)}
                    >
                      {pageNum}
                    </Button>
                  );
                })}
                {pagination.total_pages > 5 && (
                  <>
                    <span className="text-theme-secondary">...</span>
                    <Button
                      variant={pagination.current_page === pagination.total_pages ? 'primary' : 'outline'}
                      size="sm"
                      onClick={() => handlePageChange(pagination.total_pages)}
                    >
                      {pagination.total_pages}
                    </Button>
                  </>
                )}
              </div>
              
              <Button
                variant="outline"
                size="sm"
                disabled={pagination.current_page === pagination.total_pages}
                onClick={() => handlePageChange(pagination.current_page + 1)}
              >
                Next
              </Button>
            </div>
          )}
        </div>

        <div className="border-t border-theme p-6">
          <div className="flex items-center justify-between">
            <div className="text-sm text-theme-secondary">
              Showing {deliveries.length} of {pagination.total_count} deliveries
            </div>
            <Button variant="primary" onClick={onClose}>
              Close
            </Button>
          </div>
        </div>
      </div>
    </Modal>
  );
};