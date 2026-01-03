import React, { useState, useEffect, useCallback } from 'react';
import {
  ShieldCheck,
  ShieldX,
  ShieldAlert,
  Clock,
  RefreshCw,
  Filter,
  CheckCircle,
  XCircle,
  AlertTriangle,
  ChevronDown,
  ChevronUp,
  User,
  GitBranch,
  Box,
  Timer,
  MessageSquare,
  ExternalLink,
  Ban,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import {
  GitPipelineApproval,
  GitPipelineApprovalDetail,
  ApprovalStats,
  ApprovalStatus,
  PaginationInfo,
} from '@/features/git-providers/types';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ApprovalGateCard } from './ApprovalGateCard';

// ================================
// TYPES
// ================================

interface ApprovalFilters {
  status: ApprovalStatus | '';
  environment: string;
  search: string;
}

// ================================
// UTILITY FUNCTIONS
// ================================

const formatTimeRemaining = (expiresAt?: string): string => {
  if (!expiresAt) return 'No expiry';

  const now = new Date();
  const expiry = new Date(expiresAt);
  const diff = expiry.getTime() - now.getTime();

  if (diff <= 0) return 'Expired';

  const hours = Math.floor(diff / (1000 * 60 * 60));
  const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));

  if (hours > 24) {
    const days = Math.floor(hours / 24);
    return `${days}d ${hours % 24}h`;
  }
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  return `${minutes}m`;
};

const getStatusColor = (status: ApprovalStatus): string => {
  switch (status) {
    case 'pending':
      return 'text-theme-warning bg-theme-warning/10';
    case 'approved':
      return 'text-theme-success bg-theme-success/10';
    case 'rejected':
      return 'text-theme-danger bg-theme-danger/10';
    case 'expired':
      return 'text-theme-secondary bg-theme-bg';
    case 'cancelled':
      return 'text-theme-secondary bg-theme-bg';
    default:
      return 'text-theme-secondary bg-theme-bg';
  }
};

const getStatusIcon = (status: ApprovalStatus) => {
  switch (status) {
    case 'pending':
      return <Clock className="w-4 h-4" />;
    case 'approved':
      return <CheckCircle className="w-4 h-4" />;
    case 'rejected':
      return <XCircle className="w-4 h-4" />;
    case 'expired':
      return <AlertTriangle className="w-4 h-4" />;
    case 'cancelled':
      return <Ban className="w-4 h-4" />;
    default:
      return <Clock className="w-4 h-4" />;
  }
};

// ================================
// APPROVAL MODAL COMPONENT
// ================================

interface ApprovalModalProps {
  isOpen: boolean;
  approval: GitPipelineApprovalDetail | null;
  action: 'approve' | 'reject' | null;
  onClose: () => void;
  onSubmit: (comment: string) => Promise<void>;
  loading: boolean;
}

const ApprovalModal: React.FC<ApprovalModalProps> = ({
  isOpen,
  approval,
  action,
  onClose,
  onSubmit,
  loading,
}) => {
  const [comment, setComment] = useState('');

  useEffect(() => {
    if (isOpen) {
      setComment('');
    }
  }, [isOpen]);

  if (!isOpen || !approval || !action) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    await onSubmit(comment);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-theme-surface border border-theme rounded-lg shadow-xl w-full max-w-md">
        <div className="p-4 border-b border-theme">
          <div className="flex items-center gap-3">
            <div
              className={`p-2 rounded-lg ${
                action === 'approve' ? 'bg-theme-success/10' : 'bg-theme-danger/10'
              }`}
            >
              {action === 'approve' ? (
                <ShieldCheck className="w-5 h-5 text-theme-success" />
              ) : (
                <ShieldX className="w-5 h-5 text-theme-danger" />
              )}
            </div>
            <div>
              <h2 className="text-lg font-semibold text-theme-primary">
                {action === 'approve' ? 'Approve Request' : 'Reject Request'}
              </h2>
              <p className="text-sm text-theme-secondary">
                {approval.gate_name} - {approval.environment || 'No environment'}
              </p>
            </div>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="p-4 space-y-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              <MessageSquare className="w-4 h-4 inline mr-1" />
              Comment {action === 'reject' && <span className="text-theme-danger">*</span>}
            </label>
            <textarea
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              placeholder={
                action === 'approve'
                  ? 'Optional comment...'
                  : 'Please provide a reason for rejection...'
              }
              rows={3}
              required={action === 'reject'}
              className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary placeholder:text-theme-secondary/50 resize-none"
            />
          </div>

          <div className="bg-theme-bg rounded-lg p-3 space-y-2">
            <div className="flex items-center justify-between text-sm">
              <span className="text-theme-secondary">Pipeline</span>
              <span className="text-theme-primary font-medium">
                {approval.pipeline?.name || 'N/A'}
              </span>
            </div>
            <div className="flex items-center justify-between text-sm">
              <span className="text-theme-secondary">Requested by</span>
              <span className="text-theme-primary">
                {approval.requested_by?.name || approval.requested_by?.email || 'Unknown'}
              </span>
            </div>
            {approval.expires_at && (
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-secondary">Expires in</span>
                <span
                  className={`font-medium ${
                    new Date(approval.expires_at) < new Date()
                      ? 'text-theme-danger'
                      : 'text-theme-primary'
                  }`}
                >
                  {formatTimeRemaining(approval.expires_at)}
                </span>
              </div>
            )}
          </div>

          <div className="flex items-center justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              disabled={loading}
              className="px-4 py-2 text-theme-secondary hover:text-theme-primary"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading || (action === 'reject' && !comment.trim())}
              className={`flex items-center gap-2 px-4 py-2 rounded-lg font-medium text-white disabled:opacity-50 ${
                action === 'approve'
                  ? 'bg-theme-success hover:bg-theme-success'
                  : 'bg-theme-danger hover:bg-theme-danger'
              }`}
            >
              {loading ? (
                <RefreshCw className="w-4 h-4 animate-spin" />
              ) : action === 'approve' ? (
                <CheckCircle className="w-4 h-4" />
              ) : (
                <XCircle className="w-4 h-4" />
              )}
              {action === 'approve' ? 'Approve' : 'Reject'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

// ================================
// MAIN COMPONENT
// ================================

export const PipelineApprovalsPage: React.FC = () => {
  const { currentUser } = useAuth();
  const { showNotification } = useNotifications();

  // State
  const [approvals, setApprovals] = useState<GitPipelineApproval[]>([]);
  const [stats, setStats] = useState<ApprovalStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [page, setPage] = useState(1);

  // Filters
  const [filters, setFilters] = useState<ApprovalFilters>({
    status: '',
    environment: '',
    search: '',
  });
  const [showFilters, setShowFilters] = useState(false);
  const [environments, setEnvironments] = useState<string[]>([]);

  // Modal state
  const [selectedApproval, setSelectedApproval] = useState<GitPipelineApprovalDetail | null>(null);
  const [modalAction, setModalAction] = useState<'approve' | 'reject' | null>(null);
  const [modalLoading, setModalLoading] = useState(false);

  // Expanded rows for mobile/detailed view
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());

  const canManageApprovals = currentUser?.permissions?.includes('git.approvals.manage');
  const canRespondToApprovals = currentUser?.permissions?.includes('git.approvals.respond');

  // Fetch approvals - use primitive dependencies to avoid loops
  const fetchApprovals = useCallback(async () => {
    setLoading(true);
    try {
      const result = await gitProvidersApi.getApprovals({
        page,
        per_page: 20,
        status: filters.status || undefined,
        environment: filters.environment || undefined,
        sort: 'created_at',
        direction: 'desc',
      });

      setApprovals(result.approvals);
      setStats(result.stats);
      setPagination(result.pagination);

      // Extract unique environments for filter dropdown
      const envs = new Set<string>();
      result.approvals.forEach((a) => {
        if (a.environment) envs.add(a.environment);
      });
      setEnvironments(Array.from(envs).sort());
    } catch {
      showNotification('Failed to load approvals', 'error');
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, filters.status, filters.environment]);

  // Fetch approvals when page or filters change
  useEffect(() => {
    fetchApprovals();
    // Use primitive dependencies to prevent loops
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, filters.status, filters.environment]);

  // Auto-refresh for pending approvals - use ref to avoid dependency on fetchApprovals
  useEffect(() => {
    const hasPending = approvals.some((a) => a.status === 'pending');
    if (!hasPending) return;

    const interval = setInterval(() => {
      // Refetch directly without depending on callback reference
      gitProvidersApi.getApprovals({
        page,
        per_page: 20,
        status: filters.status || undefined,
        environment: filters.environment || undefined,
        sort: 'created_at',
        direction: 'desc',
      }).then((result) => {
        setApprovals(result.approvals);
        setStats(result.stats);
        setPagination(result.pagination);
      }).catch(() => {
        // Silently fail on auto-refresh
      });
    }, 30000); // Refresh every 30 seconds

    return () => clearInterval(interval);
    // Only depend on whether there are pending approvals and current filter values
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [approvals.some((a) => a.status === 'pending'), page, filters.status, filters.environment]);

  // Handlers
  const handleApprove = async (approval: GitPipelineApproval) => {
    try {
      const detail = await gitProvidersApi.getApproval(approval.id);
      setSelectedApproval(detail);
      setModalAction('approve');
    } catch {
      showNotification('Failed to load approval details', 'error');
    }
  };

  const handleReject = async (approval: GitPipelineApproval) => {
    try {
      const detail = await gitProvidersApi.getApproval(approval.id);
      setSelectedApproval(detail);
      setModalAction('reject');
    } catch {
      showNotification('Failed to load approval details', 'error');
    }
  };

  const handleModalSubmit = async (comment: string) => {
    if (!selectedApproval || !modalAction) return;

    setModalLoading(true);
    try {
      if (modalAction === 'approve') {
        await gitProvidersApi.approveRequest(selectedApproval.id, comment || undefined);
        showNotification(`Approval granted for "${selectedApproval.gate_name}"`, 'success');
      } else {
        await gitProvidersApi.rejectRequest(selectedApproval.id, comment);
        showNotification(`Request rejected for "${selectedApproval.gate_name}"`, 'success');
      }

      setSelectedApproval(null);
      setModalAction(null);
      fetchApprovals();
    } catch {
      showNotification(`Failed to ${modalAction} request`, 'error');
    } finally {
      setModalLoading(false);
    }
  };

  const handleCancel = async (approval: GitPipelineApproval) => {
    if (!confirm(`Are you sure you want to cancel the approval request for "${approval.gate_name}"?`)) {
      return;
    }

    try {
      await gitProvidersApi.cancelApprovalRequest(approval.id);
      showNotification('Approval request cancelled', 'success');
      fetchApprovals();
    } catch {
      showNotification('Failed to cancel approval request', 'error');
    }
  };

  const toggleRowExpansion = (id: string) => {
    setExpandedRows((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  };

  // Filter approvals by search
  const filteredApprovals = approvals.filter((approval) => {
    if (!filters.search) return true;
    const search = filters.search.toLowerCase();
    return (
      approval.gate_name.toLowerCase().includes(search) ||
      approval.pipeline?.name?.toLowerCase().includes(search) ||
      approval.environment?.toLowerCase().includes(search) ||
      approval.requested_by?.name?.toLowerCase().includes(search)
    );
  });

  // Get pending count for badge
  const pendingCount = stats?.pending || 0;

  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: fetchApprovals,
      variant: 'outline' as const,
      icon: RefreshCw,
    },
  ];

  if (loading && approvals.length === 0) {
    return (
      <PageContainer
        title="Pipeline Approvals"
        description="Review and respond to pipeline approval requests"
        breadcrumbs={[
          { label: 'CI/CD', href: '/app/ci-cd' },
          { label: 'Approvals' },
        ]}
      >
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Pipeline Approvals"
      description="Review and respond to pipeline approval requests"
      breadcrumbs={[
        { label: 'CI/CD', href: '/app/ci-cd' },
        { label: 'Approvals' },
      ]}
      actions={actions}
    >
      {/* Stats Overview */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center gap-2 text-theme-secondary mb-1">
              <ShieldAlert className="w-4 h-4" />
              <span className="text-sm">Total</span>
            </div>
            <p className="text-2xl font-bold text-theme-primary">{stats.total}</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center gap-2 text-theme-warning mb-1">
              <Clock className="w-4 h-4" />
              <span className="text-sm">Pending</span>
            </div>
            <p className="text-2xl font-bold text-theme-warning">{stats.pending}</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center gap-2 text-theme-success mb-1">
              <CheckCircle className="w-4 h-4" />
              <span className="text-sm">Approved</span>
            </div>
            <p className="text-2xl font-bold text-theme-success">{stats.approved}</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center gap-2 text-theme-danger mb-1">
              <XCircle className="w-4 h-4" />
              <span className="text-sm">Rejected</span>
            </div>
            <p className="text-2xl font-bold text-theme-danger">{stats.rejected}</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-center gap-2 text-theme-secondary mb-1">
              <AlertTriangle className="w-4 h-4" />
              <span className="text-sm">Expired</span>
            </div>
            <p className="text-2xl font-bold text-theme-secondary">{stats.expired}</p>
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="bg-theme-surface border border-theme rounded-lg p-4 mb-6">
        <div className="flex flex-wrap items-center gap-4">
          {/* Search */}
          <div className="flex-1 min-w-[200px]">
            <input
              type="text"
              value={filters.search}
              onChange={(e) => setFilters({ ...filters, search: e.target.value })}
              placeholder="Search approvals..."
              className="w-full bg-theme-bg border border-theme rounded-lg px-3 py-2 text-theme-primary"
            />
          </div>

          {/* Status Filter */}
          <div className="w-[150px]">
            <select
              value={filters.status}
              onChange={(e) => setFilters({ ...filters, status: e.target.value as ApprovalStatus | '' })}
              className="w-full bg-theme-surface border border-theme rounded-lg px-3 py-2 text-theme-primary [&>option]:bg-theme-surface [&>option]:text-theme-primary"
            >
              <option value="">All Status</option>
              <option value="pending">Pending</option>
              <option value="approved">Approved</option>
              <option value="rejected">Rejected</option>
              <option value="expired">Expired</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </div>

          {/* Environment Filter */}
          <div className="w-[150px]">
            <select
              value={filters.environment}
              onChange={(e) => setFilters({ ...filters, environment: e.target.value })}
              className="w-full bg-theme-surface border border-theme rounded-lg px-3 py-2 text-theme-primary [&>option]:bg-theme-surface [&>option]:text-theme-primary"
            >
              <option value="">All Environments</option>
              {environments.map((env) => (
                <option key={env} value={env}>
                  {env}
                </option>
              ))}
            </select>
          </div>

          {/* Toggle Advanced Filters */}
          <button
            onClick={() => setShowFilters(!showFilters)}
            className="flex items-center gap-1 px-3 py-2 text-theme-secondary hover:text-theme-primary"
          >
            <Filter className="w-4 h-4" />
            {showFilters ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
          </button>
        </div>
      </div>

      {/* Pending Approvals Section (if any) */}
      {pendingCount > 0 && filters.status !== 'pending' && (
        <div className="mb-6">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-theme-secondary uppercase tracking-wide">
              Awaiting Your Response ({pendingCount})
            </h3>
            <button
              onClick={() => setFilters({ ...filters, status: 'pending' })}
              className="text-sm text-theme-primary hover:underline"
            >
              View All Pending
            </button>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {approvals
              .filter((a) => a.status === 'pending' && a.can_user_approve)
              .slice(0, 3)
              .map((approval) => (
                <ApprovalGateCard
                  key={approval.id}
                  approval={approval}
                  onApprove={() => handleApprove(approval)}
                  onReject={() => handleReject(approval)}
                  canRespond={canRespondToApprovals || false}
                />
              ))}
          </div>
        </div>
      )}

      {/* Approvals Table */}
      {filteredApprovals.length > 0 ? (
        <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
          <table className="w-full">
            <thead className="bg-theme-bg">
              <tr>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Gate / Environment
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Pipeline
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Requested By
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Status
                </th>
                <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">
                  Expires
                </th>
                <th className="px-4 py-3 text-right text-sm font-medium text-theme-secondary">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredApprovals.map((approval) => {
                const isExpanded = expandedRows.has(approval.id);
                const isPending = approval.status === 'pending';
                const isExpiringSoon =
                  isPending &&
                  approval.expires_at &&
                  new Date(approval.expires_at).getTime() - Date.now() < 3600000; // Less than 1 hour

                return (
                  <React.Fragment key={approval.id}>
                    <tr
                      className={`hover:bg-theme-bg/50 ${
                        isPending ? 'bg-theme-warning/5' : ''
                      } ${isExpiringSoon ? 'border-l-4 border-l-theme-warning' : ''}`}
                    >
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => toggleRowExpansion(approval.id)}
                            className="p-1 hover:bg-theme-bg rounded"
                          >
                            {isExpanded ? (
                              <ChevronUp className="w-4 h-4 text-theme-secondary" />
                            ) : (
                              <ChevronDown className="w-4 h-4 text-theme-secondary" />
                            )}
                          </button>
                          <div>
                            <p className="text-theme-primary font-medium">{approval.gate_name}</p>
                            {approval.environment && (
                              <div className="flex items-center gap-1 text-sm text-theme-secondary">
                                <Box className="w-3 h-3" />
                                {approval.environment}
                              </div>
                            )}
                          </div>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <GitBranch className="w-4 h-4 text-theme-secondary" />
                          <span className="text-theme-primary">
                            {approval.pipeline?.name || 'N/A'}
                          </span>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <User className="w-4 h-4 text-theme-secondary" />
                          <span className="text-theme-primary">
                            {approval.requested_by?.name ||
                              approval.requested_by?.email ||
                              'Unknown'}
                          </span>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <span
                          className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${getStatusColor(
                            approval.status
                          )}`}
                        >
                          {getStatusIcon(approval.status)}
                          {approval.status.charAt(0).toUpperCase() + approval.status.slice(1)}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        {isPending && approval.expires_at ? (
                          <div
                            className={`flex items-center gap-1 text-sm ${
                              isExpiringSoon ? 'text-theme-warning font-medium' : 'text-theme-secondary'
                            }`}
                          >
                            <Timer className="w-4 h-4" />
                            {formatTimeRemaining(approval.expires_at)}
                          </div>
                        ) : (
                          <span className="text-sm text-theme-secondary">-</span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center justify-end gap-2">
                          {isPending && approval.can_user_approve && canRespondToApprovals && (
                            <>
                              <button
                                onClick={() => handleApprove(approval)}
                                className="p-1.5 hover:bg-theme-success/10 rounded text-theme-success"
                                title="Approve"
                              >
                                <CheckCircle className="w-4 h-4" />
                              </button>
                              <button
                                onClick={() => handleReject(approval)}
                                className="p-1.5 hover:bg-theme-danger/10 rounded text-theme-danger"
                                title="Reject"
                              >
                                <XCircle className="w-4 h-4" />
                              </button>
                            </>
                          )}
                          {isPending && canManageApprovals && (
                            <button
                              onClick={() => handleCancel(approval)}
                              className="p-1.5 hover:bg-theme-bg rounded text-theme-secondary hover:text-theme-danger"
                              title="Cancel Request"
                            >
                              <Ban className="w-4 h-4" />
                            </button>
                          )}
                          <button
                            onClick={() => toggleRowExpansion(approval.id)}
                            className="p-1.5 hover:bg-theme-bg rounded text-theme-secondary hover:text-theme-primary"
                            title="View Details"
                          >
                            <ExternalLink className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>

                    {/* Expanded Row */}
                    {isExpanded && (
                      <tr className="bg-theme-bg/30">
                        <td colSpan={6} className="px-4 py-4">
                          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                            <div>
                              <span className="text-theme-secondary block mb-1">Created</span>
                              <span className="text-theme-primary">
                                {new Date(approval.created_at).toLocaleString()}
                              </span>
                            </div>
                            {approval.responded_at && (
                              <div>
                                <span className="text-theme-secondary block mb-1">Responded</span>
                                <span className="text-theme-primary">
                                  {new Date(approval.responded_at).toLocaleString()}
                                </span>
                              </div>
                            )}
                            <div>
                              <span className="text-theme-secondary block mb-1">Pipeline Status</span>
                              <span className="text-theme-primary">
                                {approval.pipeline?.status || 'Unknown'}
                              </span>
                            </div>
                            <div>
                              <span className="text-theme-secondary block mb-1">Can Respond</span>
                              <span className={approval.can_user_approve ? 'text-theme-success' : 'text-theme-secondary'}>
                                {approval.can_user_approve ? 'Yes' : 'No'}
                              </span>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </React.Fragment>
                );
              })}
            </tbody>
          </table>

          {/* Pagination */}
          {pagination && pagination.total_pages > 1 && (
            <div className="px-4 py-3 border-t border-theme flex items-center justify-between">
              <p className="text-sm text-theme-secondary">
                Page {pagination.current_page} of {pagination.total_pages} ({pagination.total_count}{' '}
                total)
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  disabled={page === 1}
                  className="px-3 py-1 border border-theme rounded text-sm disabled:opacity-50"
                >
                  Previous
                </button>
                <button
                  onClick={() => setPage((p) => p + 1)}
                  disabled={page >= pagination.total_pages}
                  className="px-3 py-1 border border-theme rounded text-sm disabled:opacity-50"
                >
                  Next
                </button>
              </div>
            </div>
          )}
        </div>
      ) : (
        <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
          <ShieldAlert className="w-12 h-12 mx-auto text-theme-secondary mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">No Approvals Found</h3>
          <p className="text-theme-secondary mb-4">
            {filters.status || filters.environment || filters.search
              ? 'No approvals match your current filters.'
              : 'No approval requests have been created yet.'}
          </p>
          {(filters.status || filters.environment || filters.search) && (
            <button
              onClick={() => setFilters({ status: '', environment: '', search: '' })}
              className="text-theme-primary hover:underline"
            >
              Clear Filters
            </button>
          )}
        </div>
      )}

      {/* Approval Modal */}
      <ApprovalModal
        isOpen={!!selectedApproval && !!modalAction}
        approval={selectedApproval}
        action={modalAction}
        onClose={() => {
          setSelectedApproval(null);
          setModalAction(null);
        }}
        onSubmit={handleModalSubmit}
        loading={modalLoading}
      />
    </PageContainer>
  );
};

export default PipelineApprovalsPage;
