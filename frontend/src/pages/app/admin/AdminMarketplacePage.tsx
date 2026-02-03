/**
 * Admin Marketplace Page
 *
 * Consolidated admin interface for managing all marketplace template types
 * (workflows, pipelines, integrations, prompts) and reviews.
 */

import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
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
  Download,
  Package,
  Flag,
  ThumbsUp,
  FileCheck,
  Clock
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { marketplaceApi } from '@/features/app/services/marketplaceApi';
import type {
  MarketplaceItem,
  MarketplaceItemType,
  MarketplaceReview
} from '@/features/app/types/marketplace';
import { ALL_MARKETPLACE_TYPES } from '@/features/app/types/marketplace';

interface AdminMarketplacePageProps {
  className?: string;
}

const ALL_TYPES = ALL_MARKETPLACE_TYPES;

export const AdminMarketplacePage: React.FC<AdminMarketplacePageProps> = ({ className = '' }) => {
  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'admin',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });

  const [activeTab, setActiveTab] = useState<'items' | 'pending' | 'reviews' | 'analytics'>('items');
  const [items, setItems] = useState<MarketplaceItem[]>([]);
  const [pendingTemplates, setPendingTemplates] = useState<MarketplaceItem[]>([]);
  const [reviews, setReviews] = useState<MarketplaceReview[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedType, setSelectedType] = useState<MarketplaceItemType | 'all'>('all');
  const [selectedItem, setSelectedItem] = useState<MarketplaceItem | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [showRejectModal, setShowRejectModal] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [templateToReject, setTemplateToReject] = useState<MarketplaceItem | null>(null);
  const [reviewStatusFilter, setReviewStatusFilter] = useState<string>('all');
  const { addNotification } = useNotifications();

  // Prevent duplicate API calls in StrictMode
  const hasLoadedRef = useRef(false);
  const currentTabRef = useRef<'items' | 'pending' | 'reviews' | 'analytics'>('items');

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app' },
    { label: 'Administration', href: '/app/admin' },
    { label: 'Marketplace' }
  ];

  const getPageActions = (): PageAction[] => {
    return [
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
  };

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      if (activeTab === 'items') {
        const filters = selectedType !== 'all' ? { types: [selectedType] } : undefined;
        const response = await marketplaceApi.getItems(filters, 1, 100);
        setItems(response.data || []);
      } else if (activeTab === 'pending') {
        const response = await marketplaceApi.getPendingTemplates();
        setPendingTemplates(response.data || []);
      } else if (activeTab === 'reviews') {
        const params: { sort?: 'recent'; verified?: boolean } = { sort: 'recent' };
        const response = await marketplaceApi.getReviews(params);
        setReviews(response.data || []);
      }
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Error',
        message: error instanceof Error ? error.message : 'Failed to load data'
      });
    } finally {
      setLoading(false);
    }
  }, [activeTab, selectedType, addNotification]);

  const handleExportReport = () => {
    try {
      let data: Record<string, unknown>[];
      let filename: string;

      if (activeTab === 'items') {
        data = items.map(item => ({
          id: item.id,
          name: item.name,
          type: item.type,
          description: item.description,
          status: item.status,
          category: item.category,
          version: item.version,
          rating: item.rating,
          install_count: item.install_count,
          is_verified: item.is_verified,
          is_featured: item.is_featured,
          created_at: item.created_at
        }));
        filename = `marketplace-items-${new Date().toISOString().split('T')[0]}.csv`;
      } else if (activeTab === 'reviews') {
        data = reviews.map(review => ({
          id: review.id,
          rating: review.rating,
          title: review.title,
          author: review.author.name,
          moderation_status: review.moderation_status,
          verified_purchase: review.verified_purchase,
          helpful_count: review.helpful_count,
          created_at: review.created_at
        }));
        filename = `marketplace-reviews-${new Date().toISOString().split('T')[0]}.csv`;
      } else {
        addNotification({
          type: 'warning',
          title: 'Export not available',
          message: 'Export not available for this tab'
        });
        return;
      }

      if (data.length === 0) {
        addNotification({
          type: 'warning',
          title: 'No data',
          message: 'No data to export'
        });
        return;
      }

      // Generate CSV
      const headers = Object.keys(data[0]);
      const csvRows = [
        headers.join(','),
        ...data.map(row =>
          headers.map(header => {
            const value = row[header];
            const stringValue = value === null || value === undefined ? '' : String(value);
            if (stringValue.includes(',') || stringValue.includes('\n') || stringValue.includes('"')) {
              return `"${stringValue.replace(/"/g, '""')}"`;
            }
            return stringValue;
          }).join(',')
        )
      ];
      const csvContent = csvRows.join('\n');

      // Create and trigger download
      const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
      const link = document.createElement('a');
      link.href = URL.createObjectURL(blob);
      link.download = filename;
      link.click();
      URL.revokeObjectURL(link.href);

      addNotification({
        type: 'success',
        title: 'Export Complete',
        message: `Exported ${data.length} records to ${filename}`
      });
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export data'
      });
    }
  };

  const handleApproveTemplate = async (template: MarketplaceItem) => {
    try {
      setLoading(true);
      await marketplaceApi.approveTemplate(template.type, template.id);
      addNotification({
        type: 'success',
        title: 'Template Approved',
        message: `${template.name} has been approved for the marketplace`
      });
      await loadData();
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Error',
        message: error instanceof Error ? error.message : 'Failed to approve template'
      });
    } finally {
      setLoading(false);
    }
  };

  const handleRejectTemplate = async () => {
    if (!templateToReject || !rejectReason.trim()) {
      addNotification({
        type: 'warning',
        title: 'Rejection Reason Required',
        message: 'Please provide a reason for rejecting this template'
      });
      return;
    }

    try {
      setLoading(true);
      await marketplaceApi.rejectTemplate(templateToReject.type, templateToReject.id, rejectReason);
      addNotification({
        type: 'success',
        title: 'Template Rejected',
        message: `${templateToReject.name} has been rejected`
      });
      setShowRejectModal(false);
      setRejectReason('');
      setTemplateToReject(null);
      await loadData();
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Error',
        message: error instanceof Error ? error.message : 'Failed to reject template'
      });
    } finally {
      setLoading(false);
    }
  };

  const openRejectModal = (template: MarketplaceItem) => {
    setTemplateToReject(template);
    setRejectReason('');
    setShowRejectModal(true);
  };

  const handleReviewAction = async (reviewId: string, action: 'approve' | 'reject' | 'flag') => {
    try {
      setLoading(true);

      switch (action) {
        case 'approve':
          // Note: This would need a backend endpoint for admin approval
          addNotification({
            type: 'info',
            title: 'Admin Approval',
            message: 'Admin review approval functionality coming soon'
          });
          break;
        case 'reject':
          // Note: This would need a backend endpoint for admin rejection
          addNotification({
            type: 'info',
            title: 'Admin Rejection',
            message: 'Admin review rejection functionality coming soon'
          });
          break;
        case 'flag':
          await marketplaceApi.flagReview(reviewId);
          addNotification({
            type: 'success',
            title: 'Review Flagged',
            message: 'Review has been flagged for moderation'
          });
          break;
      }

      await loadData();
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Error',
        message: error instanceof Error ? error.message : `Failed to ${action} review`
      });
    } finally {
      setLoading(false);
    }
  };

  const getTypeBadgeColor = (type: string) => {
    switch (type) {
      // Feature-aligned types
      case 'workflow_template':
        return 'info';
      case 'pipeline_template':
        return 'success';
      case 'integration_template':
        return 'warning';
      case 'prompt_template':
        return 'default';
      // Legacy types
      case 'app':
        return 'info';
      case 'plugin':
        return 'success';
      case 'template':
        return 'warning';
      case 'integration':
        return 'default';
      default:
        return 'default';
    }
  };

  const formatTypeName = (type: string): string => {
    return type
      .split('_')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  };

  const getStatusBadgeVariant = (status: string) => {
    switch (status) {
      case 'published':
      case 'approved':
        return 'success';
      case 'draft':
      case 'pending':
        return 'warning';
      case 'rejected':
      case 'flagged':
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
      case 'flagged':
        return <XCircle className="w-4 h-4" />;
      case 'pending':
        return <AlertTriangle className="w-4 h-4" />;
      default:
        return null;
    }
  };

  const filteredItems = items.filter(item =>
    (selectedType === 'all' || item.type === selectedType) &&
    (item.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      item.description?.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  const filteredReviews = reviews.filter(review =>
    (reviewStatusFilter === 'all' || review.moderation_status === reviewStatusFilter) &&
    (review.title?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      review.content?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      review.author.name.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  useEffect(() => {
    if (!hasLoadedRef.current || currentTabRef.current !== activeTab) {
      hasLoadedRef.current = true;
      currentTabRef.current = activeTab;
      loadData();
    }
  }, [activeTab, loadData]);

  // Reload when type filter changes
  useEffect(() => {
    if (activeTab === 'items' && hasLoadedRef.current) {
      loadData();
    }
  }, [selectedType, activeTab, loadData]);

  const tabs = [
    { id: 'items' as const, label: 'Items', icon: '📦', count: items.length },
    { id: 'pending' as const, label: 'Pending Review', icon: '⏳', count: pendingTemplates.length },
    { id: 'reviews' as const, label: 'Reviews', icon: '⭐', count: reviews.length },
    { id: 'analytics' as const, label: 'Analytics', icon: '📊', count: 0 }
  ];

  const getButtonClass = (isActive: boolean) => {
    return `px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
      isActive
        ? 'bg-theme-interactive-primary text-theme-on-primary'
        : 'bg-theme-surface text-theme-tertiary hover:bg-theme-surface-hover border border-theme'
    }`;
  };

  const renderItemsTab = () => (
    <div className="space-y-6">
      {/* Search and Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-secondary w-4 h-4" />
          <input
            type="text"
            placeholder="Search items..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:ring-2 focus:ring-theme-info focus:border-transparent"
          />
        </div>

        {/* Type filter */}
        <div className="flex items-center gap-2">
          <Filter className="w-4 h-4 text-theme-tertiary" />
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
              {formatTypeName(type)}s
            </button>
          ))}
        </div>
      </div>

      {/* Items List */}
      <div className="grid gap-4">
        {loading && <div className="text-center py-8 text-theme-secondary">Loading items...</div>}
        {!loading && filteredItems.length === 0 && (
          <div className="text-center py-8 text-theme-secondary">
            {searchTerm ? 'No items match your search.' : 'No items found.'}
          </div>
        )}
        {filteredItems.map((item) => (
          <Card key={item.id} className="p-6">
            <div className="flex items-start justify-between">
              <div className="flex items-center space-x-4">
                <div className="w-12 h-12 rounded-lg bg-theme-surface border border-theme flex items-center justify-center">
                  {item.icon ? (
                    <img
                      src={item.icon}
                      alt={item.name}
                      className="w-8 h-8 rounded object-cover"
                    />
                  ) : (
                    <Package className="w-6 h-6 text-theme-tertiary" />
                  )}
                </div>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <h3 className="text-lg font-semibold text-theme-primary">{item.name}</h3>
                    {item.is_verified && (
                      <span title="Verified">
                        <CheckCircle className="w-4 h-4 text-theme-info" />
                      </span>
                    )}
                    {item.is_featured && (
                      <span title="Featured">
                        <Star className="w-4 h-4 text-theme-warning fill-current" />
                      </span>
                    )}
                  </div>
                  <p className="text-sm text-theme-secondary line-clamp-1">{item.description}</p>
                  <div className="flex items-center space-x-4 mt-2">
                    <Badge variant={getTypeBadgeColor(item.type) as 'success' | 'warning' | 'danger' | 'info' | 'default'}>
                      {formatTypeName(item.type)}
                    </Badge>
                    <Badge variant={getStatusBadgeVariant(item.status) as 'success' | 'warning' | 'danger' | 'info' | 'default'} className="flex items-center space-x-1">
                      {getStatusIcon(item.status)}
                      <span className="capitalize">{item.status}</span>
                    </Badge>
                    <span className="text-sm text-theme-secondary">
                      v{item.version}
                    </span>
                    <span className="text-sm text-theme-secondary flex items-center gap-1">
                      <Star className="w-3 h-3 text-theme-warning fill-current" />
                      {item.rating.toFixed(1)}
                    </span>
                    <span className="text-sm text-theme-secondary">
                      {item.install_count.toLocaleString()} subscribers
                    </span>
                  </div>
                </div>
              </div>

              <div className="flex items-center space-x-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setSelectedItem(item);
                    setShowDetails(true);
                  }}
                  title="View Details"
                >
                  <Eye className="w-4 h-4" />
                </Button>

                {item.is_featured ? (
                  <Button
                    variant="outline"
                    size="sm"
                    title="Remove Featured"
                  >
                    <Star className="w-4 h-4 fill-current text-theme-warning" />
                  </Button>
                ) : (
                  <Button
                    variant="outline"
                    size="sm"
                    title="Feature Item"
                  >
                    <Star className="w-4 h-4" />
                  </Button>
                )}

                <Button
                  variant="ghost"
                  size="sm"
                  title="Delete Item"
                  className="text-theme-danger hover:text-theme-danger"
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

  const filteredPendingTemplates = pendingTemplates.filter(template =>
    (selectedType === 'all' || template.type === selectedType) &&
    (template.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      template.description?.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  const renderPendingTab = () => (
    <div className="space-y-6">
      {/* Search and Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-secondary w-4 h-4" />
          <input
            type="text"
            placeholder="Search pending templates..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:ring-2 focus:ring-theme-info focus:border-transparent"
          />
        </div>

        {/* Type filter */}
        <div className="flex items-center gap-2">
          <Filter className="w-4 h-4 text-theme-tertiary" />
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
              {formatTypeName(type)}s
            </button>
          ))}
        </div>
      </div>

      {/* Pending Templates List */}
      <div className="grid gap-4">
        {loading && <div className="text-center py-8 text-theme-secondary">Loading pending templates...</div>}
        {!loading && filteredPendingTemplates.length === 0 && (
          <div className="text-center py-12">
            <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-theme-success bg-opacity-10 flex items-center justify-center">
              <FileCheck className="w-8 h-8 text-theme-success" />
            </div>
            <h3 className="text-lg font-semibold text-theme-primary mb-2">No Pending Templates</h3>
            <p className="text-theme-secondary">
              {searchTerm ? 'No templates match your search.' : 'All templates have been reviewed.'}
            </p>
          </div>
        )}
        {filteredPendingTemplates.map((template) => (
          <Card key={template.id} className="p-6">
            <div className="flex items-start justify-between">
              <div className="flex items-center space-x-4">
                <div className="w-12 h-12 rounded-lg bg-theme-warning bg-opacity-10 flex items-center justify-center">
                  <Clock className="w-6 h-6 text-theme-warning" />
                </div>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <h3 className="text-lg font-semibold text-theme-primary">{template.name}</h3>
                  </div>
                  <p className="text-sm text-theme-secondary line-clamp-2">{template.description}</p>
                  <div className="flex items-center space-x-4 mt-2">
                    <Badge variant={getTypeBadgeColor(template.type) as 'success' | 'warning' | 'danger' | 'info' | 'default'}>
                      {formatTypeName(template.type)}
                    </Badge>
                    <Badge variant="warning" className="flex items-center space-x-1">
                      <AlertTriangle className="w-3 h-3" />
                      <span>Pending Review</span>
                    </Badge>
                    {template.category && (
                      <span className="text-sm text-theme-tertiary">
                        {template.category}
                      </span>
                    )}
                    {template.version && (
                      <span className="text-sm text-theme-tertiary">
                        v{template.version}
                      </span>
                    )}
                  </div>
                  {template.publisher && (
                    <div className="mt-2 text-sm text-theme-tertiary">
                      Submitted by: <span className="font-medium text-theme-secondary">{template.publisher.display_name}</span>
                    </div>
                  )}
                </div>
              </div>

              <div className="flex items-center space-x-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setSelectedItem(template);
                    setShowDetails(true);
                  }}
                  title="View Details"
                >
                  <Eye className="w-4 h-4" />
                </Button>

                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => handleApproveTemplate(template)}
                  disabled={loading}
                  title="Approve Template"
                  className="text-theme-success border-theme-success hover:bg-theme-success hover:text-white"
                >
                  <CheckCircle className="w-4 h-4" />
                </Button>

                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => openRejectModal(template)}
                  disabled={loading}
                  title="Reject Template"
                  className="text-theme-danger border-theme-danger hover:bg-theme-danger hover:text-white"
                >
                  <XCircle className="w-4 h-4" />
                </Button>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );

  const renderReviewsTab = () => (
    <div className="space-y-6">
      {/* Search and Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-secondary w-4 h-4" />
          <input
            type="text"
            placeholder="Search reviews..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:ring-2 focus:ring-theme-info focus:border-transparent"
          />
        </div>

        {/* Status filter */}
        <div className="flex items-center gap-2">
          <Filter className="w-4 h-4 text-theme-tertiary" />
          <button
            onClick={() => setReviewStatusFilter('all')}
            className={getButtonClass(reviewStatusFilter === 'all')}
          >
            All
          </button>
          <button
            onClick={() => setReviewStatusFilter('pending')}
            className={getButtonClass(reviewStatusFilter === 'pending')}
          >
            Pending
          </button>
          <button
            onClick={() => setReviewStatusFilter('approved')}
            className={getButtonClass(reviewStatusFilter === 'approved')}
          >
            Approved
          </button>
          <button
            onClick={() => setReviewStatusFilter('flagged')}
            className={getButtonClass(reviewStatusFilter === 'flagged')}
          >
            Flagged
          </button>
        </div>
      </div>

      {/* Reviews List */}
      <div className="grid gap-4">
        {loading && <div className="text-center py-8 text-theme-secondary">Loading reviews...</div>}
        {!loading && filteredReviews.length === 0 && (
          <div className="text-center py-8 text-theme-secondary">
            {searchTerm ? 'No reviews match your search.' : 'No reviews found.'}
          </div>
        )}
        {filteredReviews.map((review) => (
          <Card key={review.id} className="p-6">
            <div className="flex items-start justify-between">
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-2">
                  {/* Rating stars */}
                  <div className="flex items-center gap-1">
                    {[1, 2, 3, 4, 5].map((star) => (
                      <Star
                        key={star}
                        className={`w-4 h-4 ${star <= review.rating ? 'text-theme-warning fill-current' : 'text-theme-tertiary'}`}
                      />
                    ))}
                  </div>
                  <Badge variant={getStatusBadgeVariant(review.moderation_status) as 'success' | 'warning' | 'danger' | 'info' | 'default'} className="flex items-center space-x-1">
                    {getStatusIcon(review.moderation_status)}
                    <span className="capitalize">{review.moderation_status}</span>
                  </Badge>
                  {review.verified_purchase && (
                    <Badge variant="success" className="flex items-center space-x-1">
                      <CheckCircle className="w-3 h-3" />
                      <span>Verified</span>
                    </Badge>
                  )}
                </div>

                {review.title && (
                  <h3 className="text-lg font-semibold text-theme-primary mb-1">
                    {review.title}
                  </h3>
                )}

                {review.content && (
                  <p className="text-sm text-theme-secondary mb-2 line-clamp-2">
                    {review.content}
                  </p>
                )}

                <div className="flex items-center gap-4 text-sm text-theme-tertiary">
                  <span>By {review.author.name}</span>
                  <span>{new Date(review.created_at).toLocaleDateString()}</span>
                  <span className="flex items-center gap-1">
                    <ThumbsUp className="w-3 h-3" />
                    {review.helpful_count} found helpful
                  </span>
                  {review.reviewable && (
                    <span>
                      For: {review.reviewable.name} ({review.reviewable.type})
                    </span>
                  )}
                </div>
              </div>

              <div className="flex items-center space-x-2">
                {review.moderation_status === 'pending' && (
                  <>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleReviewAction(review.id, 'approve')}
                      disabled={loading}
                      title="Approve Review"
                    >
                      <CheckCircle className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleReviewAction(review.id, 'reject')}
                      disabled={loading}
                      title="Reject Review"
                    >
                      <XCircle className="w-4 h-4" />
                    </Button>
                  </>
                )}

                {review.moderation_status !== 'flagged' && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleReviewAction(review.id, 'flag')}
                    disabled={loading}
                    title="Flag Review"
                  >
                    <Flag className="w-4 h-4" />
                  </Button>
                )}
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );

  const renderAnalyticsTab = () => (
    <div className="text-center py-12">
      <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-theme-info bg-opacity-10 flex items-center justify-center">
        <TrendingUp className="w-8 h-8 text-theme-info" />
      </div>
      <h3 className="text-lg font-semibold text-theme-primary mb-2">Analytics Coming Soon</h3>
      <p className="text-theme-secondary">
        This section will provide marketplace analytics and insights.
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
                  ? 'border-theme-info text-theme-info'
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
      {activeTab === 'items' && renderItemsTab()}
      {activeTab === 'pending' && renderPendingTab()}
      {activeTab === 'reviews' && renderReviewsTab()}
      {activeTab === 'analytics' && renderAnalyticsTab()}

      {/* Item Details Modal */}
      {showDetails && selectedItem && (
        <Modal
          isOpen={showDetails}
          onClose={() => setShowDetails(false)}
          title="Item Details"
          maxWidth="lg"
        >
          <div className="space-y-4">
            <div className="flex items-center space-x-4">
              <div className="w-16 h-16 rounded-lg bg-theme-surface border border-theme flex items-center justify-center">
                {selectedItem.icon ? (
                  <img
                    src={selectedItem.icon}
                    alt={selectedItem.name}
                    className="w-12 h-12 rounded object-cover"
                  />
                ) : (
                  <Package className="w-8 h-8 text-theme-tertiary" />
                )}
              </div>
              <div>
                <h3 className="text-xl font-semibold text-theme-primary">{selectedItem.name}</h3>
                <p className="text-theme-secondary">
                  {formatTypeName(selectedItem.type)} v{selectedItem.version}
                </p>
              </div>
            </div>

            <div className="space-y-3">
              <div>
                <label className="text-sm font-medium text-theme-primary">Description</label>
                <p className="text-theme-secondary">{selectedItem.description || 'No description provided'}</p>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-sm font-medium text-theme-primary">Status</label>
                  <div className="mt-1">
                    <Badge variant={getStatusBadgeVariant(selectedItem.status) as 'success' | 'warning' | 'danger' | 'info' | 'default'} className="flex items-center space-x-1 w-fit">
                      {getStatusIcon(selectedItem.status)}
                      <span className="capitalize">{selectedItem.status}</span>
                    </Badge>
                  </div>
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-primary">Category</label>
                  <p className="text-theme-secondary">{selectedItem.category}</p>
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-primary">Rating</label>
                  <p className="text-theme-secondary flex items-center gap-1">
                    <Star className="w-4 h-4 text-theme-warning fill-current" />
                    {selectedItem.rating.toFixed(1)} ({selectedItem.rating_count} reviews)
                  </p>
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-primary">Subscribers</label>
                  <p className="text-theme-secondary">{selectedItem.install_count.toLocaleString()}</p>
                </div>
              </div>

              {selectedItem.tags && selectedItem.tags.length > 0 && (
                <div>
                  <label className="text-sm font-medium text-theme-primary">Tags</label>
                  <div className="flex flex-wrap gap-2 mt-1">
                    {selectedItem.tags.map((tag, index) => (
                      <Badge key={index} variant="secondary">{tag}</Badge>
                    ))}
                  </div>
                </div>
              )}

              <div>
                <label className="text-sm font-medium text-theme-primary">Created</label>
                <p className="text-theme-secondary">{new Date(selectedItem.created_at).toLocaleDateString()}</p>
              </div>
            </div>

            <div className="flex justify-end space-x-3 pt-4 border-t border-theme">
              <Button variant="outline" onClick={() => setShowDetails(false)}>
                Close
              </Button>
            </div>
          </div>
        </Modal>
      )}

      {/* Reject Template Modal */}
      {showRejectModal && templateToReject && (
        <Modal
          isOpen={showRejectModal}
          onClose={() => {
            setShowRejectModal(false);
            setTemplateToReject(null);
            setRejectReason('');
          }}
          title="Reject Template"
          maxWidth="md"
        >
          <div className="space-y-4">
            <p className="text-theme-secondary">
              You are about to reject <span className="font-semibold text-theme-primary">{templateToReject.name}</span> from the marketplace.
            </p>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Rejection Reason <span className="text-theme-danger">*</span>
              </label>
              <textarea
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                placeholder="Please provide a reason for rejecting this template..."
                rows={4}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:ring-2 focus:ring-theme-info focus:border-transparent resize-none"
              />
              <p className="text-xs text-theme-tertiary mt-1">
                This feedback will be sent to the publisher.
              </p>
            </div>

            <div className="flex justify-end space-x-3 pt-4 border-t border-theme">
              <Button
                variant="outline"
                onClick={() => {
                  setShowRejectModal(false);
                  setTemplateToReject(null);
                  setRejectReason('');
                }}
              >
                Cancel
              </Button>
              <Button
                variant="danger"
                onClick={handleRejectTemplate}
                disabled={loading || !rejectReason.trim()}
              >
                {loading ? 'Rejecting...' : 'Reject Template'}
              </Button>
            </div>
          </div>
        </Modal>
      )}
    </PageContainer>
  );
};

export default AdminMarketplacePage;
