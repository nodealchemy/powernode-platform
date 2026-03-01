import React from 'react';
import { X, ShieldAlert, AlertTriangle, Clock, User } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useQuarantineRecord } from '../api/securityExtApi';
import type { QuarantineSeverity, QuarantineStatus } from '../types/security';

const SEVERITY_VARIANTS: Record<QuarantineSeverity, 'danger' | 'warning' | 'info' | 'default'> = {
  critical: 'danger',
  high: 'warning',
  medium: 'default',
  low: 'info',
};

const STATUS_VARIANTS: Record<QuarantineStatus, 'danger' | 'success' | 'default'> = {
  active: 'danger',
  restored: 'success',
  expired: 'default',
};

interface QuarantineDetailPanelProps {
  recordId: string;
  onClose: () => void;
}

export const QuarantineDetailPanel: React.FC<QuarantineDetailPanelProps> = ({ recordId, onClose }) => {
  const { data: record, isLoading } = useQuarantineRecord(recordId);

  if (isLoading) {
    return (
      <Card className="p-6">
        <LoadingSpinner size="sm" />
      </Card>
    );
  }

  if (!record) {
    return null;
  }

  return (
    <Card className="p-6 border border-theme">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 bg-theme-error bg-opacity-10 rounded-lg flex items-center justify-center">
            <ShieldAlert className="h-5 w-5 text-theme-error" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">Quarantine Details</h3>
            <p className="text-sm text-theme-secondary">Agent: {record.agent_id}</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <Badge variant={SEVERITY_VARIANTS[record.severity]} size="sm">
            {record.severity}
          </Badge>
          <Badge variant={STATUS_VARIANTS[record.status]} size="sm">
            {record.status}
          </Badge>
          <Button variant="ghost" size="xs" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Info Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <div className="flex items-start gap-3 p-3 bg-theme-bg rounded-lg">
          <AlertTriangle className="h-4 w-4 text-theme-muted mt-0.5" />
          <div>
            <p className="text-xs text-theme-tertiary">Trigger Reason</p>
            <p className="text-sm text-theme-primary">{record.trigger_reason}</p>
          </div>
        </div>
        <div className="flex items-start gap-3 p-3 bg-theme-bg rounded-lg">
          <ShieldAlert className="h-4 w-4 text-theme-muted mt-0.5" />
          <div>
            <p className="text-xs text-theme-tertiary">Trigger Source</p>
            <p className="text-sm text-theme-primary">{record.trigger_source}</p>
          </div>
        </div>
        <div className="flex items-start gap-3 p-3 bg-theme-bg rounded-lg">
          <Clock className="h-4 w-4 text-theme-muted mt-0.5" />
          <div>
            <p className="text-xs text-theme-tertiary">Cooldown</p>
            <p className="text-sm text-theme-primary">
              {record.cooldown_minutes != null ? `${record.cooldown_minutes} minutes` : '--'}
            </p>
          </div>
        </div>
        <div className="flex items-start gap-3 p-3 bg-theme-bg rounded-lg">
          <Clock className="h-4 w-4 text-theme-muted mt-0.5" />
          <div>
            <p className="text-xs text-theme-tertiary">Scheduled Restore</p>
            <p className="text-sm text-theme-primary">
              {record.scheduled_restore_at ? new Date(record.scheduled_restore_at).toLocaleString() : '--'}
            </p>
          </div>
        </div>
        {record.approved_by_id && (
          <div className="flex items-start gap-3 p-3 bg-theme-bg rounded-lg">
            <User className="h-4 w-4 text-theme-muted mt-0.5" />
            <div>
              <p className="text-xs text-theme-tertiary">Approved By</p>
              <p className="text-sm text-theme-primary">{record.approved_by_id}</p>
            </div>
          </div>
        )}
        {record.restored_at && (
          <div className="flex items-start gap-3 p-3 bg-theme-bg rounded-lg">
            <Clock className="h-4 w-4 text-theme-muted mt-0.5" />
            <div>
              <p className="text-xs text-theme-tertiary">Restored At</p>
              <p className="text-sm text-theme-primary">{new Date(record.restored_at).toLocaleString()}</p>
            </div>
          </div>
        )}
      </div>

      {/* Restoration Notes */}
      {record.restoration_notes && (
        <div className="bg-theme-success bg-opacity-5 border border-theme rounded-lg p-4 mb-6">
          <h4 className="text-sm font-medium text-theme-success mb-1">Restoration Notes</h4>
          <p className="text-sm text-theme-secondary">{record.restoration_notes}</p>
        </div>
      )}

      {/* Restrictions Applied */}
      {record.restrictions_applied && Object.keys(record.restrictions_applied).length > 0 && (
        <div className="mb-6">
          <h4 className="text-sm font-medium text-theme-primary mb-2">Restrictions Applied</h4>
          <div className="bg-theme-bg rounded-lg p-3">
            <pre className="text-xs text-theme-secondary overflow-x-auto whitespace-pre-wrap">
              {JSON.stringify(record.restrictions_applied, null, 2)}
            </pre>
          </div>
        </div>
      )}

      {/* Forensic Snapshot */}
      {record.forensic_snapshot && Object.keys(record.forensic_snapshot).length > 0 && (
        <div>
          <h4 className="text-sm font-medium text-theme-primary mb-2">Forensic Snapshot</h4>
          <div className="bg-theme-bg rounded-lg p-3 max-h-80 overflow-y-auto">
            <pre className="text-xs text-theme-secondary overflow-x-auto whitespace-pre-wrap">
              {JSON.stringify(record.forensic_snapshot, null, 2)}
            </pre>
          </div>
        </div>
      )}

      {/* Escalation Chain */}
      {record.escalated_from_id && (
        <div className="mt-6 pt-4 border-t border-theme">
          <p className="text-xs text-theme-tertiary">
            Escalated from record: <span className="font-mono">{record.escalated_from_id}</span>
          </p>
        </div>
      )}
    </Card>
  );
};
