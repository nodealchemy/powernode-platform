import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { FlexItemsCenter, FlexBetween, FlexCol } from '@/shared/components/ui/FlexContainer';
import { GridCols2 } from '@/shared/components/ui/GridContainer';
import { App } from '../../types';
import { 
  Globe, 
  Calendar, 
  Star, 
  Code, 
  Webhook, 
  Settings, 
  Plus,
  ExternalLink,
  Tag,
  Clock
} from 'lucide-react';

interface AppDetailsModalProps {
  isOpen: boolean;
  onClose: () => void;
  app: App | null;
  isOwner?: boolean;
  showSubscription?: boolean;
  onSubscribe?: (app: App) => void;
  onManage?: (app: App) => void;
}

export const AppDetailsModal: React.FC<AppDetailsModalProps> = ({
  isOpen,
  onClose,
  app,
  isOwner = false,
  showSubscription = false,
  onSubscribe,
  onManage
}) => {
  const [activeTab, setActiveTab] = useState<'overview' | 'features' | 'pricing' | 'reviews'>('overview');

  if (!app) return null;

  const getStatusBadgeVariant = (status: string): 'success' | 'warning' | 'danger' | 'secondary' => {
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

  const mockFeatures = [
    { name: 'API Integration', description: 'Connect with external services', icon: '🔌' },
    { name: 'Real-time Updates', description: 'Live data synchronization', icon: '⚡' },
    { name: 'Custom Webhooks', description: 'Event-driven notifications', icon: '🔔' },
    { name: 'Analytics Dashboard', description: 'Comprehensive reporting', icon: '📊' },
    { name: 'Multi-tenant Support', description: 'Isolated data per account', icon: '🏢' },
    { name: 'Advanced Security', description: 'Enterprise-grade protection', icon: '🔒' }
  ];

  const mockReviews = [
    {
      id: '1',
      user: 'John Smith',
      rating: 5,
      comment: 'Excellent app! Easy to integrate and very reliable.',
      date: '2024-01-15'
    },
    {
      id: '2',
      user: 'Sarah Johnson',
      rating: 4,
      comment: 'Great functionality, could use better documentation.',
      date: '2024-01-10'
    },
    {
      id: '3',
      user: 'Mike Chen',
      rating: 5,
      comment: 'Perfect for our use case. Highly recommended!',
      date: '2024-01-08'
    }
  ];

  const averageRating = mockReviews.reduce((sum, review) => sum + review.rating, 0) / mockReviews.length;

  const tabs = [
    { id: 'overview' as const, label: 'Overview', icon: '📋' },
    { id: 'features' as const, label: 'Features', icon: '⚙️' },
    { id: 'pricing' as const, label: 'Pricing', icon: '💰' },
    { id: 'reviews' as const, label: 'Reviews', icon: '⭐' }
  ];

  const renderOverviewTab = () => (
    <div className="space-y-6">
      {/* App Header */}
      <div className="flex items-start space-x-6">
        <div className="w-20 h-20 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white text-3xl">
          {app.icon || '📱'}
        </div>
        <div className="flex-1">
          <h3 className="text-2xl font-bold text-theme-primary mb-2">{app.name}</h3>
          <p className="text-theme-secondary mb-4">{app.description}</p>
          <div className="flex items-center space-x-4 mb-4">
            <Badge variant={getStatusBadgeVariant(app.status)}>
              {formatStatus(app.status)}
            </Badge>
            <span className="text-sm text-theme-tertiary">Version {app.version}</span>
            <FlexItemsCenter gap="xs">
              <Star className="w-4 h-4 text-theme-warning fill-current" />
              <span className="text-sm font-medium">{averageRating.toFixed(1)}</span>
              <span className="text-sm text-theme-tertiary">({mockReviews.length} reviews)</span>
            </FlexItemsCenter>
          </div>
        </div>
      </div>

      {/* Quick Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card className="p-4 text-center">
          <div className="text-2xl font-bold text-theme-primary">1.2k</div>
          <div className="text-sm text-theme-secondary">Active Users</div>
        </Card>
        <Card className="p-4 text-center">
          <div className="text-2xl font-bold text-theme-primary">99.9%</div>
          <div className="text-sm text-theme-secondary">Uptime</div>
        </Card>
        <Card className="p-4 text-center">
          <div className="text-2xl font-bold text-theme-primary">24/7</div>
          <div className="text-sm text-theme-secondary">Support</div>
        </Card>
        <Card className="p-4 text-center">
          <div className="text-2xl font-bold text-theme-primary">15+</div>
          <div className="text-sm text-theme-secondary">Integrations</div>
        </Card>
      </div>

      {/* App Info */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <Card className="p-6">
          <h4 className="text-lg font-semibold text-theme-primary mb-4">App Information</h4>
          <div className="space-y-3">
            <div className="flex items-center space-x-3">
              <Globe className="w-5 h-5 text-theme-secondary" />
              <div>
                <div className="font-medium text-theme-primary">Category</div>
                <div className="text-sm text-theme-secondary">{app.category}</div>
              </div>
            </div>
            <div className="flex items-center space-x-3">
              <Calendar className="w-5 h-5 text-theme-secondary" />
              <div>
                <div className="font-medium text-theme-primary">Last Updated</div>
                <div className="text-sm text-theme-secondary">
                  {new Date(app.updated_at).toLocaleDateString()}
                </div>
              </div>
            </div>
            <div className="flex items-center space-x-3">
              <Clock className="w-5 h-5 text-theme-secondary" />
              <div>
                <div className="font-medium text-theme-primary">Published</div>
                <div className="text-sm text-theme-secondary">
                  {app.published_at ? new Date(app.published_at).toLocaleDateString() : 'Not published'}
                </div>
              </div>
            </div>
          </div>
        </Card>

        <Card className="p-6">
          <h4 className="text-lg font-semibold text-theme-primary mb-4">Technical Details</h4>
          <div className="space-y-3">
            <div className="flex items-center space-x-3">
              <Code className="w-5 h-5 text-theme-secondary" />
              <div>
                <div className="font-medium text-theme-primary">API Endpoints</div>
                <div className="text-sm text-theme-secondary">12 endpoints available</div>
              </div>
            </div>
            <div className="flex items-center space-x-3">
              <Webhook className="w-5 h-5 text-theme-secondary" />
              <div>
                <div className="font-medium text-theme-primary">Webhooks</div>
                <div className="text-sm text-theme-secondary">5 webhook events</div>
              </div>
            </div>
            <div className="flex items-center space-x-3">
              <Settings className="w-5 h-5 text-theme-secondary" />
              <div>
                <div className="font-medium text-theme-primary">Configuration</div>
                <div className="text-sm text-theme-secondary">Highly customizable</div>
              </div>
            </div>
          </div>
        </Card>
      </div>

      {/* Tags */}
      {app.tags && app.tags.length > 0 && (
        <Card className="p-6">
          <h4 className="text-lg font-semibold text-theme-primary mb-4 flex items-center space-x-2">
            <Tag className="w-5 h-5" />
            <span>Tags</span>
          </h4>
          <div className="flex flex-wrap gap-2">
            {app.tags.map((tag) => (
              <Badge key={tag} variant="outline" className="text-sm">
                {tag}
              </Badge>
            ))}
          </div>
        </Card>
      )}
    </div>
  );

  const renderFeaturesTab = () => (
    <div className="space-y-4">
      <h4 className="text-xl font-semibold text-theme-primary">Key Features</h4>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {mockFeatures.map((feature, index) => (
          <Card key={index} className="p-6">
            <div className="flex items-start space-x-4">
              <div className="text-2xl">{feature.icon}</div>
              <div>
                <h5 className="font-semibold text-theme-primary mb-2">{feature.name}</h5>
                <p className="text-sm text-theme-secondary">{feature.description}</p>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );

  const renderPricingTab = () => (
    <div className="space-y-4">
      <h4 className="text-xl font-semibold text-theme-primary">Pricing Plans</h4>
      <div className="text-center py-12">
        <div className="text-6xl mb-4">💰</div>
        <h5 className="text-lg font-semibold text-theme-primary mb-2">Pricing Details</h5>
        <p className="text-theme-secondary mb-4">
          View detailed pricing information when subscribing to this app.
        </p>
        {showSubscription && !isOwner && (
          <Button
            variant="primary"
            onClick={() => onSubscribe?.(app)}
            className="flex items-center space-x-2 mx-auto"
          >
            <Plus className="w-4 h-4" />
            <span>View Subscription Plans</span>
          </Button>
        )}
      </div>
    </div>
  );

  const renderReviewsTab = () => (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h4 className="text-xl font-semibold text-theme-primary">User Reviews</h4>
        <div className="flex items-center space-x-2">
          <div className="flex items-center space-x-1">
            {[1, 2, 3, 4, 5].map((star) => (
              <Star
                key={star}
                className={`w-4 h-4 ${
                  star <= Math.round(averageRating)
                    ? 'text-theme-warning fill-current'
                    : 'text-theme-muted'
                }`}
              />
            ))}
          </div>
          <span className="font-medium">{averageRating.toFixed(1)}</span>
          <span className="text-sm text-theme-tertiary">({mockReviews.length} reviews)</span>
        </div>
      </div>
      
      <div className="space-y-4">
        {mockReviews.map((review) => (
          <Card key={review.id} className="p-6">
            <div className="flex items-start justify-between mb-2">
              <div className="flex items-center space-x-3">
                <div className="w-10 h-10 bg-theme-interactive-primary rounded-full flex items-center justify-center text-white font-semibold">
                  {review.user.charAt(0)}
                </div>
                <div>
                  <div className="font-medium text-theme-primary">{review.user}</div>
                  <div className="flex items-center space-x-1">
                    {[1, 2, 3, 4, 5].map((star) => (
                      <Star
                        key={star}
                        className={`w-3 h-3 ${
                          star <= review.rating
                            ? 'text-theme-warning fill-current'
                            : 'text-theme-muted'
                        }`}
                      />
                    ))}
                  </div>
                </div>
              </div>
              <div className="text-sm text-theme-tertiary">
                {new Date(review.date).toLocaleDateString()}
              </div>
            </div>
            <p className="text-theme-secondary">{review.comment}</p>
          </Card>
        ))}
      </div>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title=""
      maxWidth="4xl"
    >
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <div className="w-12 h-12 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white text-xl">
              {app.icon || '📱'}
            </div>
            <div>
              <h2 className="text-xl font-bold text-theme-primary">{app.name}</h2>
              <p className="text-theme-secondary">{app.short_description || app.description}</p>
            </div>
          </div>
          
          <div className="flex items-center space-x-2">
            {isOwner ? (
              <Button
                variant="outline"
                size="sm"
                onClick={() => onManage?.(app)}
                className="flex items-center space-x-2"
              >
                <Settings className="w-4 h-4" />
                <span>Manage</span>
              </Button>
            ) : showSubscription ? (
              <Button
                variant="primary"
                size="sm"
                onClick={() => onSubscribe?.(app)}
                className="flex items-center space-x-2"
              >
                <Plus className="w-4 h-4" />
                <span>Subscribe</span>
              </Button>
            ) : null}
          </div>
        </div>

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
                    : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                }`}
              >
                <span className="text-base">{tab.icon}</span>
                <span>{tab.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Tab Content */}
        <div className="min-h-[400px]">
          {activeTab === 'overview' && renderOverviewTab()}
          {activeTab === 'features' && renderFeaturesTab()}
          {activeTab === 'pricing' && renderPricingTab()}
          {activeTab === 'reviews' && renderReviewsTab()}
        </div>

        {/* Footer Actions */}
        <div className="flex items-center justify-end space-x-3 pt-4 border-t border-theme">
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
          {!isOwner && showSubscription && (
            <Button
              variant="primary"
              onClick={() => onSubscribe?.(app)}
              className="flex items-center space-x-2"
            >
              <Plus className="w-4 h-4" />
              <span>Subscribe to App</span>
            </Button>
          )}
          {isOwner && (
            <Button
              variant="primary"
              onClick={() => onManage?.(app)}
              className="flex items-center space-x-2"
            >
              <ExternalLink className="w-4 h-4" />
              <span>Manage App</span>
            </Button>
          )}
        </div>
      </div>
    </Modal>
  );
};