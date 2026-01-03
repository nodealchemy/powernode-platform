import React, { useState, useEffect } from 'react';
import {
  ShieldCheck,
  ShieldX,
  Clock,
  CheckCircle,
  XCircle,
  AlertTriangle,
  User,
  GitBranch,
  Box,
  Timer,
  Ban,
} from 'lucide-react';
import {
  GitPipelineApproval,
  ApprovalStatus,
} from '@/features/git-providers/types';

// ================================
// TYPES
// ================================

interface ApprovalGateCardProps {
  approval: GitPipelineApproval;
  onApprove: () => void;
  onReject: () => void;
  onCancel?: () => void;
  canRespond: boolean;
  canCancel?: boolean;
  compact?: boolean;
}

// ================================
// UTILITY FUNCTIONS
// ================================

const formatTimeRemaining = (expiresAt?: string): { text: string; urgent: boolean; expired: boolean } => {
  if (!expiresAt) return { text: 'No expiry', urgent: false, expired: false };

  const now = new Date();
  const expiry = new Date(expiresAt);
  const diff = expiry.getTime() - now.getTime();

  if (diff <= 0) return { text: 'Expired', urgent: true, expired: true };

  const hours = Math.floor(diff / (1000 * 60 * 60));
  const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
  const seconds = Math.floor((diff % (1000 * 60)) / 1000);

  // Urgent if less than 30 minutes
  const urgent = diff < 30 * 60 * 1000;

  if (hours > 24) {
    const days = Math.floor(hours / 24);
    return { text: `${days}d ${hours % 24}h`, urgent: false, expired: false };
  }
  if (hours > 0) {
    return { text: `${hours}h ${minutes}m`, urgent, expired: false };
  }
  if (minutes > 0) {
    return { text: `${minutes}m ${seconds}s`, urgent, expired: false };
  }
  return { text: `${seconds}s`, urgent: true, expired: false };
};

const getStatusConfig = (status: ApprovalStatus) => {
  switch (status) {
    case 'pending':
      return {
        color: 'text-theme-warning',
        bg: 'bg-theme-warning/10',
        border: 'border-theme-warning/30',
        icon: Clock,
        label: 'Pending',
      };
    case 'approved':
      return {
        color: 'text-theme-success',
        bg: 'bg-theme-success/10',
        border: 'border-theme-success/30',
        icon: CheckCircle,
        label: 'Approved',
      };
    case 'rejected':
      return {
        color: 'text-theme-danger',
        bg: 'bg-theme-danger/10',
        border: 'border-theme-danger/30',
        icon: XCircle,
        label: 'Rejected',
      };
    case 'expired':
      return {
        color: 'text-theme-secondary',
        bg: 'bg-theme-bg',
        border: 'border-theme',
        icon: AlertTriangle,
        label: 'Expired',
      };
    case 'cancelled':
      return {
        color: 'text-theme-secondary',
        bg: 'bg-theme-bg',
        border: 'border-theme',
        icon: Ban,
        label: 'Cancelled',
      };
    default:
      return {
        color: 'text-theme-secondary',
        bg: 'bg-theme-bg',
        border: 'border-theme',
        icon: Clock,
        label: status,
      };
  }
};

// ================================
// COUNTDOWN COMPONENT
// ================================

interface CountdownProps {
  expiresAt: string;
  onExpire?: () => void;
}

const Countdown: React.FC<CountdownProps> = ({ expiresAt, onExpire }) => {
  const [timeInfo, setTimeInfo] = useState(() => formatTimeRemaining(expiresAt));

  useEffect(() => {
    const interval = setInterval(() => {
      const newInfo = formatTimeRemaining(expiresAt);
      setTimeInfo(newInfo);

      if (newInfo.expired && onExpire) {
        onExpire();
        clearInterval(interval);
      }
    }, 1000);

    return () => clearInterval(interval);
  }, [expiresAt, onExpire]);

  return (
    <div
      className={`flex items-center gap-1.5 px-2 py-1 rounded-md text-xs font-medium ${
        timeInfo.expired
          ? 'bg-theme-danger/10 text-theme-danger'
          : timeInfo.urgent
          ? 'bg-theme-warning/10 text-theme-warning animate-pulse'
          : 'bg-theme-bg text-theme-secondary'
      }`}
    >
      <Timer className="w-3.5 h-3.5" />
      <span>{timeInfo.text}</span>
    </div>
  );
};

// ================================
// MAIN COMPONENT
// ================================

export const ApprovalGateCard: React.FC<ApprovalGateCardProps> = ({
  approval,
  onApprove,
  onReject,
  onCancel,
  canRespond,
  canCancel = false,
  compact = false,
}) => {
  const statusConfig = getStatusConfig(approval.status);
  const StatusIcon = statusConfig.icon;
  const isPending = approval.status === 'pending';
  const canTakeAction = isPending && canRespond && approval.can_user_approve;

  if (compact) {
    return (
      <div
        className={`flex items-center justify-between p-3 border rounded-lg ${statusConfig.border} ${statusConfig.bg}`}
      >
        <div className="flex items-center gap-3">
          <StatusIcon className={`w-5 h-5 ${statusConfig.color}`} />
          <div>
            <p className="text-sm font-medium text-theme-primary">{approval.gate_name}</p>
            <p className="text-xs text-theme-secondary">{approval.environment || 'No environment'}</p>
          </div>
        </div>

        {canTakeAction && (
          <div className="flex items-center gap-2">
            <button
              onClick={onApprove}
              className="p-1.5 bg-theme-success hover:bg-theme-success rounded text-white"
              title="Approve"
            >
              <CheckCircle className="w-4 h-4" />
            </button>
            <button
              onClick={onReject}
              className="p-1.5 bg-theme-danger hover:bg-theme-danger rounded text-white"
              title="Reject"
            >
              <XCircle className="w-4 h-4" />
            </button>
          </div>
        )}

        {!canTakeAction && isPending && approval.expires_at && (
          <Countdown expiresAt={approval.expires_at} />
        )}
      </div>
    );
  }

  return (
    <div
      className={`bg-theme-surface border rounded-lg overflow-hidden transition-shadow hover:shadow-md ${
        isPending ? 'border-theme-warning/30' : 'border-theme'
      }`}
    >
      {/* Header */}
      <div className={`p-4 ${statusConfig.bg} border-b ${statusConfig.border}`}>
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${statusConfig.bg}`}>
              <StatusIcon className={`w-5 h-5 ${statusConfig.color}`} />
            </div>
            <div>
              <h3 className="font-medium text-theme-primary">{approval.gate_name}</h3>
              <div className="flex items-center gap-2 mt-1">
                {approval.environment && (
                  <span className="flex items-center gap-1 text-xs text-theme-secondary">
                    <Box className="w-3 h-3" />
                    {approval.environment}
                  </span>
                )}
                <span
                  className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusConfig.bg} ${statusConfig.color}`}
                >
                  {statusConfig.label}
                </span>
              </div>
            </div>
          </div>

          {isPending && approval.expires_at && (
            <Countdown expiresAt={approval.expires_at} />
          )}
        </div>
      </div>

      {/* Body */}
      <div className="p-4 space-y-3">
        {/* Pipeline Info */}
        <div className="flex items-center gap-2 text-sm">
          <GitBranch className="w-4 h-4 text-theme-secondary" />
          <span className="text-theme-secondary">Pipeline:</span>
          <span className="text-theme-primary font-medium">
            {approval.pipeline?.name || 'Unknown'}
          </span>
          {approval.pipeline?.status && (
            <span
              className={`px-1.5 py-0.5 rounded text-xs ${
                approval.pipeline.status === 'running'
                  ? 'bg-theme-info/10 text-theme-info'
                  : approval.pipeline.status === 'success'
                  ? 'bg-theme-success/10 text-theme-success'
                  : 'bg-theme-bg text-theme-secondary'
              }`}
            >
              {approval.pipeline.status}
            </span>
          )}
        </div>

        {/* Requested By */}
        {approval.requested_by && (
          <div className="flex items-center gap-2 text-sm">
            <User className="w-4 h-4 text-theme-secondary" />
            <span className="text-theme-secondary">Requested by:</span>
            <span className="text-theme-primary">
              {approval.requested_by.name || approval.requested_by.email}
            </span>
          </div>
        )}

        {/* Created Time */}
        <div className="flex items-center gap-2 text-sm">
          <Clock className="w-4 h-4 text-theme-secondary" />
          <span className="text-theme-secondary">Requested:</span>
          <span className="text-theme-primary">
            {new Date(approval.created_at).toLocaleString()}
          </span>
        </div>
      </div>

      {/* Actions */}
      {(canTakeAction || canCancel) && (
        <div className="px-4 pb-4 flex items-center gap-2">
          {canTakeAction && (
            <>
              <button
                onClick={onApprove}
                className="flex-1 flex items-center justify-center gap-2 px-4 py-2 bg-theme-success hover:bg-theme-success rounded-lg text-white font-medium transition-colors"
              >
                <ShieldCheck className="w-4 h-4" />
                Approve
              </button>
              <button
                onClick={onReject}
                className="flex-1 flex items-center justify-center gap-2 px-4 py-2 bg-theme-danger hover:bg-theme-danger rounded-lg text-white font-medium transition-colors"
              >
                <ShieldX className="w-4 h-4" />
                Reject
              </button>
            </>
          )}
          {canCancel && onCancel && (
            <button
              onClick={onCancel}
              className="px-4 py-2 border border-theme rounded-lg text-theme-secondary hover:text-theme-primary hover:border-theme-primary transition-colors"
            >
              Cancel
            </button>
          )}
        </div>
      )}

      {/* Not Authorized Message */}
      {isPending && !canTakeAction && !approval.can_user_approve && (
        <div className="px-4 pb-4">
          <div className="flex items-center gap-2 p-2 bg-theme-bg rounded-lg text-sm text-theme-secondary">
            <AlertTriangle className="w-4 h-4" />
            <span>You are not authorized to respond to this approval request.</span>
          </div>
        </div>
      )}

      {/* Response Info (if already responded) */}
      {approval.responded_at && (
        <div className="px-4 pb-4">
          <div
            className={`p-2 rounded-lg text-sm ${
              approval.status === 'approved'
                ? 'bg-theme-success/10 text-theme-success'
                : approval.status === 'rejected'
                ? 'bg-theme-danger/10 text-theme-danger'
                : 'bg-theme-bg text-theme-secondary'
            }`}
          >
            <span className="font-medium">{statusConfig.label}</span>
            <span className="text-theme-secondary mx-1">at</span>
            <span>{new Date(approval.responded_at).toLocaleString()}</span>
          </div>
        </div>
      )}
    </div>
  );
};

export default ApprovalGateCard;
