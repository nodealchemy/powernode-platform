import React from 'react';
import { FileCode, Container, Shield, Building2, Scale, Clock } from 'lucide-react';

interface ActivityItem {
  id: string;
  action: string;
  entity_type: string;
  entity_name: string;
  user_name?: string;
  details?: string;
  created_at: string;
}

interface ActivityFeedProps {
  items: ActivityItem[];
  maxItems?: number;
}

const entityIcons: Record<string, typeof FileCode> = {
  sbom: FileCode,
  container_image: Container,
  attestation: Shield,
  vendor: Building2,
  license_violation: Scale,
};

function formatRelativeTime(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
}

export const ActivityFeed: React.FC<ActivityFeedProps> = ({ items, maxItems = 5 }) => {
  const displayItems = items.slice(0, maxItems);

  if (displayItems.length === 0) {
    return (
      <div className="bg-theme-surface border border-theme rounded-lg p-4">
        <h3 className="font-semibold text-theme-primary mb-3">Recent Activity</h3>
        <div className="text-center py-4">
          <Clock className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
          <p className="text-sm text-theme-secondary">No recent activity</p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4">
      <h3 className="font-semibold text-theme-primary mb-3">Recent Activity</h3>
      <div className="space-y-3">
        {displayItems.map((item) => {
          const Icon = entityIcons[item.entity_type] || FileCode;
          return (
            <div key={item.id} className="flex items-start gap-3">
              <div className="p-1.5 rounded bg-theme-primary/10">
                <Icon className="w-4 h-4 text-theme-primary" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm text-theme-primary">
                  <span className="font-medium">{item.action}</span>
                  {' '}
                  <span className="text-theme-secondary">{item.entity_name}</span>
                </p>
                {item.user_name && <p className="text-xs text-theme-tertiary">by {item.user_name}</p>}
              </div>
              <span className="text-xs text-theme-tertiary whitespace-nowrap">
                {formatRelativeTime(item.created_at)}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
};
