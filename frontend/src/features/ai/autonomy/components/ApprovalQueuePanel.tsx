import React, { useState, useCallback } from 'react';
import { CheckCircle, XCircle, Clock, AlertTriangle, ChevronDown, ChevronRight } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { EntityLink } from '@/shared/components/entity';
import { useApprovalQueue, useApproveAction, useRejectAction } from '../api/autonomyApi';
import type { ApprovalRequest } from '../types/autonomy';

const formatDate = (dateStr?: string): string => {
  if (!dateStr) return 'N/A';
  return new Date(dateStr).toLocaleString();
};

const ApprovalCard: React.FC<{
  request: ApprovalRequest;
  isExpanded: boolean;
  onToggle: () => void;
}> = ({ request, isExpanded, onToggle }) => {
  const approveMutation = useApproveAction();
  const rejectMutation = useRejectAction();

  const handleApprove = () => {
    approveMutation.mutate({ id: request.id });
  };

  const handleReject = () => {
    rejectMutation.mutate({ id: request.id });
  };

  const isPending = request.status === 'pending';
  const requestDataKeys = Object.keys(request.request_data ?? {});

  return (
    <div className="rounded-lg bg-theme-surface border border-theme overflow-hidden">
      {/* Collapsed header */}
      <div
        onClick={onToggle}
        className="flex items-start gap-3 p-4 cursor-pointer hover:bg-theme-background/50 transition-colors"
      >
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onToggle(); }}
          className="p-1 text-theme-secondary hover:text-theme-primary shrink-0"
          title={isExpanded ? 'Collapse' : 'Expand'}
        >
          {isExpanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
        </button>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <AlertTriangle className="h-4 w-4 text-theme-warning-fg shrink-0" />
            <span className="text-sm font-medium text-theme-primary truncate">
              {request.action_type}
            </span>
          </div>
          <div className="flex items-center gap-3 text-xs text-theme-tertiary">
            {request.agent_name && (
              <span className="flex items-center gap-1">
                Agent: <EntityLink type="agent" id={request.agent_id} label={request.agent_name} className="text-xs" />
              </span>
            )}
            <span>Created: {formatDate(request.created_at)}</span>
          </div>
        </div>
        <Badge
          variant={request.status === 'pending' ? 'warning' : request.status === 'approved' ? 'success' : 'default'}
          size="sm"
        >
          {request.status}
        </Badge>
      </div>

      {/* Expanded own-detail */}
      {isExpanded && (
        <div className="border-t border-theme p-4 space-y-3 bg-theme-background">
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
            <div>
              <p className="text-xs text-theme-tertiary">Action Type</p>
              <p className="text-theme-primary font-medium">{request.action_type}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary">Status</p>
              <p className="text-theme-primary font-medium capitalize">{request.status}</p>
            </div>
            {request.agent_name && (
              <div>
                <p className="text-xs text-theme-tertiary">Agent</p>
                <EntityLink type="agent" id={request.agent_id} label={request.agent_name} className="text-sm font-medium" />
              </div>
            )}
            <div>
              <p className="text-xs text-theme-tertiary">Requested</p>
              <p className="text-theme-primary font-medium">{formatDate(request.created_at)}</p>
            </div>
            {request.expires_at && (
              <div>
                <p className="text-xs text-theme-tertiary">Expires</p>
                <p className="text-theme-primary font-medium">{formatDate(request.expires_at)}</p>
              </div>
            )}
            {request.completed_at && (
              <div>
                <p className="text-xs text-theme-tertiary">Completed</p>
                <p className="text-theme-primary font-medium">{formatDate(request.completed_at)}</p>
              </div>
            )}
          </div>

          {request.description && (
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Description</p>
              <p className="text-sm text-theme-secondary">{request.description}</p>
            </div>
          )}

          {requestDataKeys.length > 0 && (
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Request Data</p>
              <pre className="text-xs bg-theme-surface border border-theme rounded p-3 overflow-auto text-theme-secondary">
                {JSON.stringify(request.request_data, null, 2)}
              </pre>
            </div>
          )}

          {isPending && (
            <div className="flex gap-2 pt-1">
              <button
                onClick={handleApprove}
                disabled={approveMutation.isPending}
                className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-theme-success-bg text-white hover:opacity-90 disabled:opacity-50"
              >
                <CheckCircle className="h-3.5 w-3.5" />
                Approve
              </button>
              <button
                onClick={handleReject}
                disabled={rejectMutation.isPending}
                className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-theme-error-bg text-white hover:opacity-90 disabled:opacity-50"
              >
                <XCircle className="h-3.5 w-3.5" />
                Reject
              </button>
            </div>
          )}
        </div>
      )}

      {/* Quick approve/reject also available without expanding */}
      {isPending && !isExpanded && (
        <div className="flex gap-2 px-4 pb-4">
          <button
            onClick={handleApprove}
            disabled={approveMutation.isPending}
            className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-theme-success-bg text-white hover:opacity-90 disabled:opacity-50"
          >
            <CheckCircle className="h-3.5 w-3.5" />
            Approve
          </button>
          <button
            onClick={handleReject}
            disabled={rejectMutation.isPending}
            className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-theme-error-bg text-white hover:opacity-90 disabled:opacity-50"
          >
            <XCircle className="h-3.5 w-3.5" />
            Reject
          </button>
        </div>
      )}
    </div>
  );
};

export const ApprovalQueuePanel: React.FC = () => {
  const { data: approvals, isLoading } = useApprovalQueue();
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  const toggleExpand = useCallback((id: string) => {
    setExpandedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }, []);

  if (isLoading) {
    return null;
  }

  return (
    <Card>
      <CardHeader title="Approval Queue" />
      <CardContent>
        {approvals && approvals.length > 0 ? (
          <div className="space-y-3">
            {approvals.map((request) => (
              <ApprovalCard
                key={request.id}
                request={request}
                isExpanded={expandedIds.has(request.id)}
                onToggle={() => toggleExpand(request.id)}
              />
            ))}
          </div>
        ) : (
          <div className="py-6 text-center text-theme-tertiary">
            <Clock className="w-10 h-10 mx-auto mb-2 opacity-30" />
            <p className="text-sm">No pending approvals</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
