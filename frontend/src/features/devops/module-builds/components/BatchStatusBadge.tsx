import React from 'react';
import { Clock, RefreshCw, ShieldCheck, UploadCloud, CheckCircle, AlertTriangle, XCircle, Ban } from 'lucide-react';
import type { ModuleBuildBatchStatus } from '../types';

interface StatusConfig {
  bg: string;
  text: string;
  icon: React.ElementType;
  label: string;
  spin?: boolean;
}

const STATUS_CONFIG: Record<ModuleBuildBatchStatus, StatusConfig> = {
  planning: { bg: 'bg-theme-warning-fg/10', text: 'text-theme-warning-fg', icon: Clock, label: 'Planning' },
  dispatched: { bg: 'bg-theme-info-fg/10', text: 'text-theme-info-fg', icon: RefreshCw, label: 'Dispatched', spin: true },
  awaiting_signature: { bg: 'bg-theme-info-fg/10', text: 'text-theme-info-fg', icon: ShieldCheck, label: 'Awaiting Signature', spin: true },
  publishing: { bg: 'bg-theme-info-fg/10', text: 'text-theme-info-fg', icon: UploadCloud, label: 'Publishing', spin: true },
  complete: { bg: 'bg-theme-success-fg/10', text: 'text-theme-success-fg', icon: CheckCircle, label: 'Complete' },
  partial: { bg: 'bg-theme-warning-fg/10', text: 'text-theme-warning-fg', icon: AlertTriangle, label: 'Partial' },
  failed: { bg: 'bg-theme-error-fg/10', text: 'text-theme-error-fg', icon: XCircle, label: 'Failed' },
  cancelled: { bg: 'bg-theme-surface/10', text: 'text-theme-secondary', icon: Ban, label: 'Cancelled' },
};

export const getBatchStatusConfig = (status: ModuleBuildBatchStatus): StatusConfig =>
  STATUS_CONFIG[status] || STATUS_CONFIG.planning;

export const BatchStatusBadge: React.FC<{ status: ModuleBuildBatchStatus; className?: string }> = ({
  status,
  className = '',
}) => {
  const config = getBatchStatusConfig(status);
  const Icon = config.icon;
  return (
    <span
      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium whitespace-nowrap ${config.bg} ${config.text} ${className}`}
    >
      <Icon className={`w-3 h-3 ${config.spin ? 'animate-spin' : ''}`} />
      {config.label}
    </span>
  );
};

export default BatchStatusBadge;
