import React from 'react';
import {
  Globe,
  Shield,
  CheckCircle,
  AlertCircle,
  Clock,
  Link as LinkIcon,
  Users,
  Activity,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import { formatDate } from '@/shared/utils/formatters';
import type { FederationPartnerSummary, FederationStatus, TrustLevel } from '@/shared/services/ai';

interface FederationPartnerCardProps {
  partner: FederationPartnerSummary;
  onSelect?: (partner: FederationPartnerSummary) => void;
  onVerify?: (partner: FederationPartnerSummary) => void;
  onSync?: (partner: FederationPartnerSummary) => void;
  className?: string;
}

const statusConfig: Record<FederationStatus, {
  variant: 'success' | 'warning' | 'danger' | 'outline' | 'info';
  label: string;
  icon: React.FC<{ className?: string }>;
}> = {
  pending: { variant: 'outline', label: 'Pending', icon: Clock },
  pending_verification: { variant: 'outline', label: 'Pending Verification', icon: Clock },
  active: { variant: 'success', label: 'Active', icon: CheckCircle },
  suspended: { variant: 'warning', label: 'Suspended', icon: AlertCircle },
  revoked: { variant: 'danger', label: 'Revoked', icon: AlertCircle },
};

const trustConfig: Record<TrustLevel, {
  variant: 'success' | 'warning' | 'danger' | 'info';
  label: string;
}> = {
  untrusted: { variant: 'danger', label: 'Untrusted' },
  basic: { variant: 'warning', label: 'Basic' },
  verified: { variant: 'info', label: 'Verified' },
  trusted: { variant: 'success', label: 'Trusted' },
  partner: { variant: 'success', label: 'Partner' },
};

export const FederationPartnerCard: React.FC<FederationPartnerCardProps> = ({
  partner,
  onSelect,
  onVerify,
  onSync,
  className,
}) => {
  const status = statusConfig[partner.status] || statusConfig.pending;
  const trust = trustConfig[partner.trust_level] || trustConfig.untrusted;
  const StatusIcon = status.icon;

  return (
    <Card
      className={cn(
        'cursor-pointer transition-all hover:shadow-md',
        'border-theme-border-primary',
        partner.status === 'active' && 'border-l-4 border-l-theme-status-success',
        className
      )}
      onClick={() => onSelect?.(partner)}
    >
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start justify-between mb-3">
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 bg-theme-bg-secondary rounded-lg flex items-center justify-center">
              <Globe className="w-5 h-5 text-theme-text-secondary" />
            </div>
            <div className="min-w-0">
              <h3 className="font-medium text-theme-text-primary truncate">
                {partner.name || partner.organization_name}
              </h3>
              <div className="flex items-center gap-2 text-xs text-theme-text-secondary">
                <LinkIcon className="w-3 h-3" />
                <span className="truncate">{partner.endpoint_url}</span>
              </div>
            </div>
          </div>
          <Badge variant={status.variant} size="sm" className="flex items-center gap-1">
            <StatusIcon className="w-3 h-3" />
            {status.label}
          </Badge>
        </div>

        {/* Trust Level */}
        <div className="flex items-center gap-2 mb-3">
          <Shield className="w-4 h-4 text-theme-text-secondary" />
          <span className="text-sm text-theme-text-secondary">Trust Level:</span>
          <Badge variant={trust.variant} size="sm">
            {trust.label}
          </Badge>
        </div>

        {/* Stats */}
        <div className="flex items-center gap-4 text-sm text-theme-text-secondary mb-3">
          <div className="flex items-center gap-1">
            <Users className="w-4 h-4" />
            <span>{partner.shared_agent_count} agents</span>
          </div>
          <div className="flex items-center gap-1">
            <Activity className="w-4 h-4" />
            <span>{partner.task_count} tasks</span>
          </div>
        </div>

        {/* Last Sync */}
        {partner.last_sync_at && (
          <div className="text-xs text-theme-text-secondary mb-3">
            Last synced: {partner.last_sync_at ? formatDate(partner.last_sync_at) : '--'}
          </div>
        )}

        {/* Footer */}
        <div className="flex items-center justify-between pt-3 border-t border-theme-border-primary">
          <div className="flex items-center gap-2">
            {partner.status === 'pending' && onVerify && (
              <Button
                variant="primary"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onVerify(partner);
                }}
              >
                Verify
              </Button>
            )}
            {partner.status === 'active' && onSync && (
              <Button
                variant="outline"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onSync(partner);
                }}
              >
                Sync Agents
              </Button>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default FederationPartnerCard;
