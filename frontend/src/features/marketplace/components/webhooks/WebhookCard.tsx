import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { AppWebhook } from '../../types';
import { Settings, Play, Pause, TestTube, BarChart, Key, Clock } from 'lucide-react';

interface WebhookCardProps {
  webhook: AppWebhook;
  onEdit?: (webhook: AppWebhook) => void;
  onToggleStatus?: (webhook: AppWebhook) => void;
  onTest?: (webhook: AppWebhook) => void;
  onViewAnalytics?: (webhook: AppWebhook) => void;
  onViewDeliveries?: (webhook: AppWebhook) => void;
  onRegenerateSecret?: (webhook: AppWebhook) => void;
}

export const WebhookCard: React.FC<WebhookCardProps> = ({
WebhookCard.displayName = 'WebhookCard';
  webhook,
  onEdit,
  onToggleStatus,
  onTest,
  onViewAnalytics,
  onViewDeliveries,
  onRegenerateSecret
}) => {
  return (
    <Card className="p-6">
      <div className="flex items-start justify-between mb-4">
        <div className="flex-1">
          <div className="flex items-center space-x-3 mb-2">
            <h3 className="font-semibold text-theme-primary">{webhook.name}</h3>
            <Badge variant={webhook.is_active ? 'success' : 'secondary'}>
              {webhook.is_active ? 'Active' : 'Inactive'}
            </Badge>
            <Badge variant="outline" className="text-xs">
              {webhook.http_method}
            </Badge>
          </div>
          
          <div className="text-sm text-theme-secondary mb-2">
            <span className="font-medium">Event:</span> {webhook.event_type}
          </div>
          
          <div className="text-sm text-theme-secondary font-mono bg-theme-surface px-3 py-1 rounded mb-2 break-all">
            {webhook.url}
          </div>
          
          {webhook.description && (
            <p className="text-theme-secondary text-sm mb-3">
              {webhook.description}
            </p>
          )}
          
          <div className="flex items-center space-x-4 text-sm text-theme-tertiary">
            <div className="flex items-center space-x-1">
              <Clock className="w-3 h-3" />
              <span>{webhook.timeout_seconds}s timeout</span>
            </div>
            <span>🔄 {webhook.max_retries} retries</span>
            {webhook.analytics && (
              <span>📊 {webhook.analytics.total_deliveries} deliveries</span>
            )}
          </div>
        </div>

        <div className="flex items-center space-x-2">
          {onViewAnalytics && webhook.analytics && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onViewAnalytics(webhook)}
              title="View Analytics"
            >
              <BarChart className="w-4 h-4" />
            </Button>
          )}
          
          {onViewDeliveries && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onViewDeliveries(webhook)}
              title="View Deliveries"
            >
              📧
            </Button>
          )}
          
          {onTest && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onTest(webhook)}
              title="Test Webhook"
            >
              <TestTube className="w-4 h-4" />
            </Button>
          )}
          
          {onRegenerateSecret && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onRegenerateSecret(webhook)}
              title="Regenerate Secret"
            >
              <Key className="w-4 h-4" />
            </Button>
          )}
          
          {onToggleStatus && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onToggleStatus(webhook)}
              title={webhook.is_active ? 'Deactivate' : 'Activate'}
            >
              {webhook.is_active ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
            </Button>
          )}
          
          {onEdit && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onEdit(webhook)}
              title="Edit Webhook"
            >
              <Settings className="w-4 h-4" />
            </Button>
          )}
        </div>
      </div>

      {webhook.analytics && (
        <div className="pt-4 border-t border-theme">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <div className="text-theme-tertiary">Success Rate</div>
              <div className="font-semibold text-theme-success">
                {webhook.analytics.success_rate.toFixed(1)}%
              </div>
            </div>
            <div>
              <div className="text-theme-tertiary">Avg Response</div>
              <div className="font-semibold text-theme-primary">
                {webhook.analytics.average_response_time.toFixed(0)}ms
              </div>
            </div>
            <div>
              <div className="text-theme-tertiary">Pending</div>
              <div className="font-semibold text-theme-warning">
                {webhook.analytics.pending_deliveries}
              </div>
            </div>
            <div>
              <div className="text-theme-tertiary">Failed</div>
              <div className="font-semibold text-theme-error">
                {webhook.analytics.failed_deliveries}
              </div>
            </div>
          </div>
        </div>
      )}

      <div className="mt-4 pt-4 border-t border-theme">
        <div className="text-xs text-theme-tertiary">
          <span className="font-medium">Secret:</span> {webhook.secret_token.slice(0, 8)}...
        </div>
      </div>
    </Card>
  );
};